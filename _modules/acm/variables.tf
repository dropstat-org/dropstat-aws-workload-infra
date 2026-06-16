variable "domain_name" {
  type        = string
  description = "Primary domain name for the certificate (e.g. *.dev-dropstat.com)"
}

variable "zone_id" {
  type        = string
  default     = null
  description = "Route53 public zone ID for automatic DNS validation. If null, validation records must be added manually."
}

variable "subject_alternative_names" {
  type    = list(string)
  default = []
}

variable "tags" {
  type    = map(string)
  default = {}
}
