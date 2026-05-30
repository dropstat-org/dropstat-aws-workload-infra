variable "name" { type = string }

variable "alb_listener_arn" {
  description = "Internal ALB listener ARN — VPC Link forwards traffic here"
  type        = string
}

variable "domain_name" {
  description = "Custom domain for the API GW stage — e.g. api-dev.dropstat.com"
  type        = string
  default     = null
}

variable "certificate_arn" {
  description = "ACM certificate ARN for the custom domain"
  type        = string
  default     = null
}

variable "services" {
  type = map(object({
    method   = string
    route    = string
    hostname = string
  }))
}

variable "throttling_burst_limit" {
  type    = number
  default = 500
}

variable "throttling_rate_limit" {
  type    = number
  default = 1000
}

variable "waf_enabled" {
  type    = bool
  default = true
}

variable "waf_rate_limit" {
  type    = number
  default = 1000
}

variable "tags" {
  type    = map(string)
  default = {}
}
