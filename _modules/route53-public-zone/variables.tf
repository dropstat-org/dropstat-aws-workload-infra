variable "domain_name" {
  type        = string
  description = "Domain name registered in Route53 (e.g. dev-dropstat.com)"
}

variable "comment" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
