variable "name" {
  description = "Name prefix for all resources (e.g. 'desktop-dev', 'admin-dev')"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name (e.g. 'desktop-dev.dropstat.com')"
  type        = string
}

variable "default_root_object" {
  description = "Default file served at root URL"
  type        = string
  default     = "index.html"
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 = US+Europe (cheapest). PriceClass_All = global."
  type        = string
  default     = "PriceClass_100"
}

variable "aliases" {
  description = "Custom domain aliases (e.g. ['desktop-dev.dropstat.com']). Requires acm_certificate_arn."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN for custom domains. Must be in us-east-1 (CloudFront requirement)."
  type        = string
  default     = ""
}

variable "spa_mode" {
  description = "Enable SPA mode: CloudFront function rewrites paths to /index.html for client-side routing (React, Vue, etc.)"
  type        = bool
  default     = true
}

variable "versioning_enabled" {
  description = "Enable S3 versioning. Useful for rollbacks."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
