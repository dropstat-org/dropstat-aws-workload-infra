variable "name" {
  description = "Name prefix for all resources (e.g. 'dropstat-dev')."
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 bucket where SFTP home directories live. Created by this module."
  type        = string
}

variable "hostname" {
  description = "Custom hostname for the SFTP endpoint (Route53 CNAME). Null = use AWS default endpoint."
  type        = string
  default     = null
}

variable "hosted_zone_id" {
  description = "Route53 hosted zone ID for the custom hostname. Required when hostname is set."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
