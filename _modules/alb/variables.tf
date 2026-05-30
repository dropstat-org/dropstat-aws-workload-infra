variable "name" { type = string }

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. If null, ALB runs HTTP only."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
