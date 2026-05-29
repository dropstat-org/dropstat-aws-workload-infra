# ============================================================
# _modules/sqs
# Creates all SQS queues for a given environment
# ============================================================

module "queues" {
  source  = "terraform-aws-modules/sqs/aws"
  version = "~> 4.0"

  for_each = toset(var.queue_names)

  name                       = each.key
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds
  sqs_managed_sse_enabled    = true

  tags = var.tags
}
