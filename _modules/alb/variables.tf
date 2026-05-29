variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  description = "Private subnets — ALB is internal, accessed via API GW VPC Link"
  type        = list(string)
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. If null, ALB runs HTTP only."
  type        = string
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}
