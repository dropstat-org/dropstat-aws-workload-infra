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
# Manual secrets (passed as variables, stored in same secret):
#   - nursa_dropstat_password
#   - nursa_dropstat_user
#   - nursa_client_id
#   - nursa_user_name
#
# Uses: terraform-aws-modules/secrets-manager ~> 2.0
# ============================================================

variable "env"  { type = string; description = "Environment name (dev, staging, prod)" }
variable "tags" { type = map(string); default = {} }

# Manual secrets — must be provided, stored in Secrets Manager
variable "nursa_dropstat_password" { type = string; sensitive = true; default = "REPLACE_ME" }
variable "nursa_dropstat_user"     { type = string; default = "REPLACE_ME" }
variable "nursa_client_id"         { type = string; sensitive = true; default = "REPLACE_ME" }
variable "nursa_user_name"         { type = string; default = "REPLACE_ME" }

# ── Auto-generated passwords ──────────────────────────────────────────────────

resource "random_password" "mqtt" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|;:,.<>?"

  # Rotate by changing the keeper value (e.g. increment rotation_month)
  keepers = { rotation = "1" }
}

resource "random_password" "jwt_secret_key" {
  length  = 64
  special = false  # Base64-safe characters for JWT

  keepers = { rotation = "1" }
}

# ── Secrets Manager secret — single JSON object for all workload secrets ──────

module "secrets" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 2.0"

  name                    = "dropstat/${var.env}/workload"
  description             = "Auto-generated + manual secrets for dropstat workload (${var.env})"
  recovery_window_in_days = 0  # dev/staging: no recovery window needed

  # All workload secrets as a single JSON object
  # Services read individual keys: secret_arn:key::
  secret_string = jsonencode({
    # ── MQ ────────────────────────────────────────────────────────────────────
    mqtt_username = "dropstat"
    mqtt_password = random_password.mqtt.result

    # ── dropstat-api ──────────────────────────────────────────────────────────
    jwt_secret_key = random_password.jwt_secret_key.result

    # ── nursa ──────────────────────────────────────────────────────────────────
    nursa_dropstat_password = var.nursa_dropstat_password
    nursa_dropstat_user     = var.nursa_dropstat_user
    nursa_client_id         = var.nursa_client_id
    nursa_user_name         = var.nursa_user_name
  })

  tags = var.tags
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "secret_arn" {
  description = "ARN of the workload secrets — use as: secret_arn:key::"
  value       = module.secrets.secret_arn
}

output "secret_name" {
  description = "Name of the secret in Secrets Manager"
  value       = module.secrets.secret_id
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
