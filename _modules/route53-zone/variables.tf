variable "zone_name" {
  type        = string
  description = "DNS zone name, e.g. dev.dropstat-np.com"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to associate with the private zone. Leave empty to auto-discover the account VPC via tm-aws-account-data."
  default     = ""
}

variable "vpc_region" {
  type        = string
  description = "AWS region of the VPC"
  default     = "us-east-2"
}

variable "comment" {
  type    = string
  default = ""
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Delete all records before destroying the zone. Needed when recreating (e.g. name change)."
}

variable "tags" {
  type    = map(string)
  default = {}
}
