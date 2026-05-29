variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets for VPC Link ENIs"
  type        = list(string)
}

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

# Services map — defines routes and hostnames for ALB host-based routing
# Example:
# services = {
#   dropstat_api = {
#     method   = "ANY"
#     route    = "/api/{proxy+}"
#     hostname = "dropstat-api.dev.internal"
#   }
# }
variable "services" {
  type = map(object({
    method   = string
    route    = string
    hostname = string
  }))
}

variable "throttling_burst_limit" {
  description = "Max concurrent requests (burst)"
  type        = number
  default     = 500
}

variable "throttling_rate_limit" {
  description = "Steady-state requests per second"
  type        = number
  default     = 1000
}

variable "waf_enabled" {
  type    = bool
  default = true
}

variable "waf_rate_limit" {
  description = "Max requests per 5 minutes per IP before blocking"
  type        = number
  default     = 1000
}

variable "tags" {
  type    = map(string)
  default = {}
}
