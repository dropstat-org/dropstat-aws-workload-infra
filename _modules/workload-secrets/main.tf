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
# Secrets Manager after first apply — Terraform ignores changes):
#   - nursa_dropstat_password
#   - nursa_dropstat_user
#   - nursa_client_id
#   - nursa_user_name
#
# Requires: Terraform >= 1.11 (terraform-aws-modules/secrets-manager ~> 2.0)
# ============================================================

variable "env" {
  type        = string
  description = "Environment name (dev, staging, prod)"
}

variable "tags" {
  type    = map(string)
  default = {}
}

# Manual secrets — update directly in Secrets Manager after first apply
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

# Read-replica connection params — stored in SSM (no credentials here)
variable "read_replica_host" {
  description = "Aurora reader endpoint — stored as SSM parameter"
  type        = string
  default     = ""
}

variable "read_replica_port" {
  description = "Aurora reader port"
  type        = number
  default     = 3306
}

variable "read_replica_dbname" {
  description = "Aurora database name for the read replica datasource"
  type        = string
  default     = "dropstat"
}

# ── Auto-generated passwords ──────────────────────────────────────────────────

resource "random_password" "mqtt" {
  length           = 32
  special          = true
  # Amazon MQ rejects passwords containing , : =
  override_special = "!#$%^&*()-_+[]{}|;<.>?"

  keepers = {
    rotation = "1"
  }
}

resource "random_password" "jwt_secret_key" {
  length  = 64
  special = false

  keepers = {
    rotation = "1"
  }
}

# ── Secrets Manager secret ────────────────────────────────────────────────────

module "secrets" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 2.0"

  name                    = "dropstat/${var.env}/workload"
  description             = "Auto-generated and manual secrets for dropstat workload (${var.env})"
  recovery_window_in_days = 0

  # sensitive() ensures the entire JSON blob is masked in plan output
  secret_string = sensitive(jsonencode({
    mqtt_username           = "dropstat"
    mqtt_password           = random_password.mqtt.result
    jwt_secret_key          = random_password.jwt_secret_key.result
    nursa_dropstat_password = var.nursa_dropstat_password
    nursa_dropstat_user     = var.nursa_dropstat_user
    nursa_client_id         = var.nursa_client_id
    nursa_user_name         = var.nursa_user_name
  }))

  # Ignore secret value changes after creation — manual secrets updated
  # directly in Secrets Manager, not via Terraform
  ignore_secret_changes = true

  tags = var.tags
}

# ── Read-replica SSM parameters (connection only — no credentials) ────────────

resource "aws_ssm_parameter" "read_replica_host" {
  count = var.read_replica_host != "" ? 1 : 0
  name  = "/${var.env}/dropstat-api/read_replica_host"
  type  = "String"
  value = var.read_replica_host
}

resource "aws_ssm_parameter" "read_replica_port" {
  count = var.read_replica_host != "" ? 1 : 0
  name  = "/${var.env}/dropstat-api/read_replica_port"
  type  = "String"
  value = tostring(var.read_replica_port)
}

resource "aws_ssm_parameter" "read_replica_dbname" {
  count = var.read_replica_host != "" ? 1 : 0
  name  = "/${var.env}/dropstat-api/read_replica_dbname"
  type  = "String"
  value = var.read_replica_dbname
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "secret_arn" {
  description = "ARN of the workload secret — use as: secret_arn:key::"
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

output "read_replica_ssm_arns" {
  description = "SSM parameter ARNs for read-replica connection (host/port/dbname). Null when read_replica_host not set."
  value = length(aws_ssm_parameter.read_replica_host) > 0 ? {
    host   = aws_ssm_parameter.read_replica_host[0].arn
    port   = aws_ssm_parameter.read_replica_port[0].arn
    dbname = aws_ssm_parameter.read_replica_dbname[0].arn
  } : null
}
