variable "name" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "cluster_name" {
  type = string
}

variable "cpu" {
  type    = number
  default = 1024
}

variable "memory" {
  type    = number
  default = 2048
}

variable "image" {
  type = string
}

variable "container_port" {
  type    = number
  default = 8080
}

variable "health_check_path" {
  type    = string
  default = "/health"
}

variable "desired_count" {
  description = "Initial task count at deploy time"
  type        = number
  default     = 1
}

variable "min_task_count" {
  description = "Minimum tasks — set to 0 for scale-to-zero"
  type        = number
  default     = 0
}

variable "max_task_count" {
  description = "Maximum tasks for scale-out"
  type        = number
  default     = 3
}

variable "scaling_target_value" {
  description = "ALB requests per target per minute to trigger scale-out"
  type        = number
  default     = 10
}

variable "alb_security_group_id" {
  description = "ALB security group — tasks only accept traffic from here"
  type        = string
}

variable "alb_arn_suffix" {
  description = "ALB ARN suffix — required for ALBRequestCountPerTarget metric"
  type        = string
}

variable "http_listener_arn" {
  type    = string
  default = null
}

variable "https_listener_arn" {
  type    = string
  default = null
}

variable "hostnames" {
  description = "Host headers for ALB routing — e.g. [\"api.dropstat.com\"]"
  type        = list(string)
}

variable "listener_rule_priority" {
  description = "ALB listener rule priority — must be unique per listener"
  type        = number
}

variable "environment_vars" {
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "ssm_param_arns" {
  type    = list(string)
  default = []
}

variable "secret_arns" {
  type    = list(string)
  default = []
}

variable "task_iam_statements" {
  type    = any
  default = {}
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
