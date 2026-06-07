variable "domain_name" {
  type        = string
  description = "Primary domain name for the certificate (e.g. *.dev.dropstat.com)"
}

variable "tags" {
  type    = map(string)
  default = {}
}
