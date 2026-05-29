variable "name" {
  description = "ECS cluster name"
  type        = string
}

variable "container_insights_enabled" {
  description = "Enable CloudWatch Container Insights (recommended for prod)"
  type        = bool
  default     = false
}

variable "tags" {
  type    = map(string)
  default = {}
}
