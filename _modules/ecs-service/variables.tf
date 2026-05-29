variable "name" {
  description = "Service name — e.g. dropstat-api-dev"
  type        = string
}

variable "cpu" {
  description = "Task CPU units (256, 512, 1024, 2048, 4096)"
  type        = number
  default     = 1024
}

variable "memory" {
  description = "Task memory in MiB"
  type        = number
  default     = 2048
}

variable "image" {
  description = "Full ECR image URI including tag — e.g. 123456.dkr.ecr.us-east-2.amazonaws.com/dropstat-prod:abc123"
  type        = string
}

variable "container_port" {
  description = "Port the container listens on"
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "ALB health check path"
  type        = string
  default     = "/actuator/health"
}

variable "desired_count" {
  description = "Initial number of tasks at deploy time"
  type        = number
  default     = 1
}

variable "min_task_count" {
  description = "Minimum tasks auto-scaling can scale in to. Set to 0 to allow scale-to-zero."
  type        = number
  default     = 0
}

variable "max_task_count" {
  description = "Maximum tasks auto-scaling can scale out to"
  type        = number
  default     = 3
}

variable "scaling_target_value" {
  description = "ALB requests per target per minute that triggers scale-out. Default 10 = scales to 0 when idle."
  type        = number
  default     = 10
}

variable "vpc_id" {
  description = "VPC ID from platform-infra"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "environment_vars" {
  description = "Non-sensitive environment variables — list of {name, value}"
  type = list(object({
    name  = string
    value = string
  }))
  default = []
}

variable "secrets" {
  description = "Secrets from SSM/Secrets Manager — list of {name, valueFrom}"
  type = list(object({
    name      = string
    valueFrom = string
  }))
  default = []
}

variable "ssm_param_arns" {
  description = "SSM parameter ARNs the execution role can read"
  type        = list(string)
  default     = []
}

variable "secret_arns" {
  description = "Secrets Manager secret ARNs the execution role can read"
  type        = list(string)
  default     = []
}

variable "task_iam_statements" {
  description = "Additional IAM statements for the task role (SQS, S3, etc.)"
  type        = any
  default     = {}
}

variable "log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
