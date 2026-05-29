variable "zone_name" {
  description = "Private hosted zone name to discover — e.g. aws.dropstat.internal"
  type        = string
}

variable "records" {
  description = <<-EOT
    DNS records in terraform-aws-modules/route53/records format.
    See: https://registry.terraform.io/modules/terraform-aws-modules/route53/aws/latest/submodules/records
    Example:
      records = [
        { name = "api.dev", type = "CNAME", ttl = 60, records = ["internal-alb.us-east-2.elb.amazonaws.com"] },
      ]
  EOT
  type    = any
  default = []
}
