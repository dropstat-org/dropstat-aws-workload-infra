variable "name"             { type = string }
variable "vpc_id"           { type = string }
variable "subnet_ids"       { type = list(string) }
variable "ecs_security_group_id" { type = string }
variable "database_name"    { type = string; default = "dropstat" }
variable "master_username"  { type = string; default = "appuser" }
variable "db_subnet_group_name" { type = string; default = null }

variable "min_capacity" { type = number; default = 0.5 }
variable "max_capacity" { type = number; default = 2.0 }

variable "skip_final_snapshot"          { type = bool;   default = true }
variable "deletion_protection"          { type = bool;   default = false }
variable "monitoring_interval"          { type = number; default = 0 }
variable "performance_insights_enabled" { type = bool;   default = false }
variable "backup_retention_period"      { type = number; default = 7 }

variable "tags" { type = map(string); default = {} }
