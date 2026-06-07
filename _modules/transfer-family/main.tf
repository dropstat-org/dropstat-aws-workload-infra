# ============================================================
# _modules/transfer-family
# AWS Transfer Family — SFTP server with Lambda IdP
#
# Architecture (mirrors prod):
#   - SFTP PUBLIC endpoint
#   - AWS_LAMBDA identity provider
#   - Credentials stored in Secrets Manager: {serverId}/{username}
#   - S3 bucket for home directories
# ============================================================

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ── S3 bucket for SFTP home directories ──────────────────────────────────────

resource "aws_s3_bucket" "sftp" {
  bucket        = var.s3_bucket_name
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_versioning" "sftp" {
  bucket = aws_s3_bucket.sftp.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "sftp" {
  bucket = aws_s3_bucket.sftp.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "sftp" {
  bucket                  = aws_s3_bucket.sftp.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── IAM role for Transfer Family users (S3 access) ───────────────────────────

resource "aws_iam_role" "sftp_user" {
  name = "${var.name}-sftp-user-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "transfer.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "sftp_user_s3" {
  name = "${var.name}-sftp-user-s3"
  role = aws_iam_role.sftp_user.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.sftp.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject", "s3:GetObject", "s3:DeleteObject",
          "s3:GetObjectVersion", "s3:DeleteObjectVersion"
        ]
        Resource = "${aws_s3_bucket.sftp.arn}/*"
      }
    ]
  })
}

# ── IAM role for Lambda function ─────────────────────────────────────────────

resource "aws_iam_role" "sftp_lambda" {
  name = "${var.name}-sftp-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "sftp_lambda_logs" {
  role       = aws_iam_role.sftp_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "sftp_lambda_secrets" {
  name = "${var.name}-sftp-lambda-secrets"
  role = aws_iam_role.sftp_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = "arn:aws:secretsmanager:${local.region}:${local.account_id}:secret:s-*"
    }]
  })
}

# ── Lambda function — sftp_authenticate ──────────────────────────────────────

data "archive_file" "sftp_lambda" {
  type        = "zip"
  source_file = "${path.module}/lambda/lambda_function.py"
  output_path = "${path.module}/lambda/sftp_authenticate.zip"
}

resource "aws_lambda_function" "sftp_authenticate" {
  function_name    = "${var.name}-sftp-authenticate"
  filename         = data.archive_file.sftp_lambda.output_path
  source_code_hash = data.archive_file.sftp_lambda.output_base64sha256
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.sftp_lambda.arn

  environment {
    variables = {
      SecretsManagerRegion = local.region
    }
  }

  tags = var.tags
}

# ── IAM role for Transfer Family server (logging + Lambda invoke) ─────────────

resource "aws_iam_role" "sftp_server" {
  name = "${var.name}-sftp-server-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "transfer.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "sftp_server_logging" {
  role       = aws_iam_role.sftp_server.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSTransferLoggingAccess"
}

resource "aws_iam_role_policy" "sftp_server_lambda" {
  name = "${var.name}-sftp-server-lambda"
  role = aws_iam_role.sftp_server.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "lambda:InvokeFunction"
      Resource = aws_lambda_function.sftp_authenticate.arn
    }]
  })
}

# Allow Transfer Family to invoke the Lambda
resource "aws_lambda_permission" "sftp_invoke" {
  statement_id  = "AllowTransferFamily"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sftp_authenticate.function_name
  principal     = "transfer.amazonaws.com"
}

# ── CloudWatch log group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "sftp" {
  name              = "/aws/transfer/${var.name}"
  retention_in_days = 7
  tags              = var.tags
}

# ── Transfer Family server ────────────────────────────────────────────────────

resource "aws_transfer_server" "this" {
  protocols              = ["SFTP"]
  endpoint_type          = "PUBLIC"
  identity_provider_type = "AWS_LAMBDA"
  function               = aws_lambda_function.sftp_authenticate.arn
  logging_role           = aws_iam_role.sftp_server.arn

  tags = merge(var.tags, var.hostname != null ? {
    "aws:transfer:customHostname" = var.hostname
  } : {})

  depends_on = [aws_cloudwatch_log_group.sftp]
}

# ── Optional: Route53 CNAME for custom hostname ───────────────────────────────

resource "aws_route53_record" "sftp" {
  count = var.hostname != null && var.hosted_zone_id != null ? 1 : 0

  zone_id = var.hosted_zone_id
  name    = var.hostname
  type    = "CNAME"
  ttl     = 300
  records = [aws_transfer_server.this.endpoint]
}
