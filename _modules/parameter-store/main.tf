# ============================================================
# _modules/parameter-store
#
# Wrapper around aws_ssm_parameter for creating multiple
# SecureString parameters under a common prefix.
#
# Values use lifecycle ignore_changes — created once with
# a placeholder, then updated via the Secrets Manager
# GitHub Actions workflow (not Terraform).
#
# Usage:
#   prefix     = "/dropstat/dev"
#   parameters = {
#     "DATABASE_URL"   = "PLACEHOLDER"
#     "JWT_SECRET_KEY" = "PLACEHOLDER"
#   }
# ============================================================

variable "prefix" {
  description = "SSM path prefix (e.g. /dropstat/dev)"
  type        = string
}

variable "parameters" {
  description = "Map of parameter name → initial placeholder value. Values managed outside Terraform."
  type        = map(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_ssm_parameter" "this" {
  for_each = var.parameters

  name        = "${var.prefix}/${each.key}"
  description = "App config — managed via Secrets Manager pipeline after creation"
  type        = "SecureString"
  value       = each.value

  # Terraform creates the parameter path — values updated by the
  # Secrets Manager GitHub Actions workflow, not on every apply.
  lifecycle {
    ignore_changes = [value]
  }

  tags = var.tags
}

output "parameter_arns" {
  description = "Map of parameter name → ARN"
  value       = { for k, v in aws_ssm_parameter.this : k => v.arn }
}

output "parameter_names" {
  description = "Map of parameter name → full SSM path"
  value       = { for k, v in aws_ssm_parameter.this : k => v.name }
}
