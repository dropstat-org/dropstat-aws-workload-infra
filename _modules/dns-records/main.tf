# ============================================================
# _modules/dns-records
#
# Creates Route53 records in an existing hosted zone.
# Accepts zone_id directly — no data lookup, no cross-account.
# The zone is created by the route53-zone module.
# ============================================================

variable "zone_id" {
  type        = string
  description = "Route53 zone ID (from route53-zone module output)"
}

variable "zone_name" {
  type        = string
  description = "Zone name — kept for backwards compat and documentation purposes"
  default     = ""
}

variable "records" {
  type = list(object({
    name    = string
    type    = string
    ttl     = number
    records = list(string)
  }))
  description = "List of DNS records to create in the zone"
}

module "records" {
  source  = "terraform-aws-modules/route53/aws//modules/records"
  version = "~> 4.0"

  zone_id = var.zone_id
  records = var.records
}
