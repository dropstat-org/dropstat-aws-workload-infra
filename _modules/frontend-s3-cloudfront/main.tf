# ============================================================
# _modules/frontend-s3-cloudfront
#
# Static frontend hosting: private S3 + CloudFront with OAC.
# S3 static website hosting is NOT used — bucket is private.
# CloudFront serves files via Origin Access Control (OAC).
#
# Deploy pattern (GitHub Actions):
#   aws s3 sync dist/ s3://{bucket_name}/ --delete
#   aws cloudfront create-invalidation --distribution-id {distribution_id} --paths "/*"
#
# Refs:
#   terraform-aws-modules/cloudfront  ~> 6.0
#   terraform-aws-modules/s3-bucket   ~> 5.0
# ============================================================

locals {
  tags = merge(var.tags, { Module = "frontend-s3-cloudfront" })
}

# ── S3 bucket — private, no website hosting ──────────────────────────────────

module "s3" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.0"

  bucket = var.bucket_name

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  versioning = {
    enabled = var.versioning_enabled
  }

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = {
        sse_algorithm = "AES256"
      }
    }
  }

  lifecycle_rule = var.versioning_enabled ? [
    {
      id      = "expire-old-versions"
      enabled = true
      noncurrent_version_expiration = {
        noncurrent_days = 90
      }
    }
  ] : []

  tags = local.tags
}

# ── S3 bucket policy — allow CloudFront OAC to read objects ──────────────────

data "aws_iam_policy_document" "s3_cloudfront" {
  statement {
    sid    = "AllowCloudFrontOAC"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${module.s3.s3_bucket_arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = module.s3.s3_bucket_id
  policy = data.aws_iam_policy_document.s3_cloudfront.json

  depends_on = [module.cloudfront]
}

# ── CloudFront distribution ───────────────────────────────────────────────────
# OAC is created by the cloudfront module internally via origin_access_control.
# Do NOT create aws_cloudfront_origin_access_control directly — it would collide
# with the module's internal resource since both use the same name.

module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "~> 6.0"

  comment             = "${var.name} frontend"
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.default_root_object
  price_class         = var.price_class
  aliases             = var.aliases

  # OAC managed by the module via origin_access_control map
  # Key "s3" is referenced via origin_access_control_key in the origin block
  origin_access_control = {
    s3 = {
      name             = "${var.name}-oac"   # unique per deployment e.g. desktop-dev-oac
      description      = "OAC for ${var.name} frontend"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  origin = {
    s3 = {
      domain_name               = module.s3.s3_bucket_bucket_regional_domain_name
      origin_access_control_key = "s3"
    }
  }

  default_cache_behavior = {
    target_origin_id       = "s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6" # CachingOptimized

    function_association = var.spa_mode ? {
      viewer-request = {
        function_arn = aws_cloudfront_function.spa_redirect[0].arn
      }
    } : {}
  }

  custom_error_response = var.spa_mode ? [
    {
      error_code            = 404
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 0
    },
    {
      error_code            = 403
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 0
    }
  ] : []

  viewer_certificate = length(var.aliases) > 0 && var.acm_certificate_arn != "" ? {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  } : {
    cloudfront_default_certificate = true
  }

  tags = local.tags
}

# ── CloudFront Function — SPA client-side routing ────────────────────────────

resource "aws_cloudfront_function" "spa_redirect" {
  count   = var.spa_mode ? 1 : 0
  name    = "${replace(var.name, "-", "_")}_spa_redirect"
  runtime = "cloudfront-js-2.0"
  comment = "SPA routing: rewrite non-file paths to /index.html"
  publish = true

  code = <<-EOF
    function handler(event) {
      var request = event.request;
      var uri = request.uri;
      if (!uri.match(/\.[a-zA-Z0-9]+$/)) {
        request.uri = '/index.html';
      }
      return request;
    }
  EOF
}
