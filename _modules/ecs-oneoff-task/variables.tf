variable "name" {
  description = "Task definition family, container name and log group suffix."
  type        = string
}

variable "image" {
  type = string
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "command" {
  description = "Arguments appended to the image entrypoint."
  type        = list(string)
  default     = []
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

variable "secret_arns" {
  description = "Secrets Manager ARNs the execution role may read to inject var.secrets."
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "tags" {
  type    = map(string)
  default = {}
}
