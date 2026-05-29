variable "zone_name" {
  description = "Private hosted zone name to discover"
  type        = string
  default     = "aws.dropstat.internal"
}

variable "env" {
  description = "Environment name used as subdomain prefix — e.g. dev, staging"
  type        = string
}

variable "alb_dns_name" {
  description = "Internal ALB DNS name — all service records point here"
  type        = string
}

variable "aurora_endpoint" {
  description = "Aurora cluster endpoint"
  type        = string
}
