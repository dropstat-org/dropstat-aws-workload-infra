# ============================================================
# _modules/dns-records
#
# Creates Route53 records in an existing private hosted zone.
# Uses aws_route53_record directly — no data source lookup —
# so it works cleanly when zone_id comes from a dependency.
# ============================================================

variable "zone_id" {
  type        = string
  description = "Route53 zone ID (from route53-zone module output)"
}

variable "zone_name" {
  type        = string
  description = "Zone name — for documentation only"
  default     = ""
}

variable "records" {
  type = list(object({
    name    = string
    type    = string
    ttl     = number
    records = list(string)
  }))
  description = "List of DNS records to create"
}

resource "aws_route53_record" "this" {
  for_each = { for r in var.records : r.name => r }

  zone_id = var.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}

output "zone_id" {
  value = var.zone_id
}
