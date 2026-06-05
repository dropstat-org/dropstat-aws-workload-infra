# ============================================================
# _modules/workload-secrets
#
# Generates and stores all workload secrets for an environment
# in a single Secrets Manager secret as a JSON object.
#
# Auto-generated secrets (random_password):
#   - mqtt_password   → MQ broker admin password
#   - jwt_secret_key  → JWT signing key for dropstat-api
#
# Manual secrets (passed as variables, updated directly in
# Secrets Manager after first apply):
#   - nursa_dropstat_password
#   - nursa_dropstat_user
#   - nursa_client_id
#   - nursa_user_name
#
# Uses native aws_secretsmanager_secret (no external module —
# avoids terraform >= 1.11 constraint from secrets-manager v2)
# ============================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.1"
    }
  }
}

variable "env" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Manual secrets — update directly in Secrets Manager after first apply:
#   AWS Console → Secrets Manager → dropstat/{env}/workload → Edit
variable "nursa_dropstat_password" {
  type      = string
  sensitive = true
  default   = "REPLACE_ME"
}

variable "nursa_dropstat_user" {
  type    = string
  default = "REPLACE_ME"
}

variable "nursa_client_id" {
  type      = string
  sensitive = true
  default   = "REPLACE_ME"
}

variable "nursa_user_name" {
  type    = string
  default = "REPLACE_ME"
}

# ── Auto-generated passwords ──────────────────────────────────────────────────

resource "random_password" "mqtt" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|;:,.<>?"

  # Rotate by incrementing the keeper value
  keepers = {
    rotation = "1"
  }
}

resource "random_password" "jwt_secret_key" {
  length  = 64
  special = false # Base64-safe for JWT

  keepers = {
    rotation = "1"
  }
}

# ── Secrets Manager secret ────────────────────────────────────────────────────

resource "aws_secretsmanager_secret" "workload" {
  name                    = "dropstat/${var.env}/workload"
  description             = "Auto-generated and manual secrets for dropstat workload (${var.env})"
  recovery_window_in_days = 0 # dev/staging: no recovery window

  tags = var.tags
}

resource "aws_secretsmanager_secret_version" "workload" {
  secret_id = aws_secretsmanager_secret.workload.id

  secret_string = jsonencode({
    # ── MQ ──────────────────────────────────────────────────────────────────
    mqtt_username = "dropstat"
    mqtt_password = random_password.mqtt.result

    # ── dropstat-api ─────────────────────────────────────────────────────────
    jwt_secret_key = random_password.jwt_secret_key.result

    # ── nursa ─────────────────────────────────────────────────────────────────
    nursa_dropstat_password = var.nursa_dropstat_password
    nursa_dropstat_user     = var.nursa_dropstat_user
    nursa_client_id         = var.nursa_client_id
    nursa_user_name         = var.nursa_user_name
  })

  # Ignore secret_string changes after creation — manual values are updated
  # directly in Secrets Manager, not via Terraform on every apply.
  lifecycle {
    ignore_changes = [secret_string]
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "secret_arn" {
  description = "ARN of the workload secret — use as: secret_arn:key::"
  value       = aws_secretsmanager_secret.workload.arn
}

output "secret_name" {
  description = "Name of the secret in Secrets Manager"
  value       = aws_secretsmanager_secret.workload.name
}

output "mqtt_username" {
  description = "MQ username (not sensitive)"
  value       = "dropstat"
}

output "mqtt_password" {
  description = "Auto-generated MQ password — passed to MQ module at apply time"
  value       = random_password.mqtt.result
  sensitive   = true
}
