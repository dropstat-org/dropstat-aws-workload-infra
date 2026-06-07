# Public Route53 hosted zone for a domain registered in Route53.
# Used for ACM certificate DNS validation — ACM needs a public zone to verify ownership.
# The same domain also has a private zone (route53-zone module) for internal resolution.
#
# Split-horizon DNS:
#   Public zone  → ACM validation records + any public-facing DNS
#   Private zone → Internal ALB records, only resolvable from within the VPC

resource "aws_route53_zone" "this" {
  name    = var.domain_name
  comment = var.comment != "" ? var.comment : "Public zone for ${var.domain_name} — ACM DNS validation"
  tags    = var.tags
}

output "zone_id" {
  description = "Route53 public zone ID — pass to ACM module as zone_id for auto-validation"
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Name servers — must match what Route53 Domains shows for the registered domain"
  value       = aws_route53_zone.this.name_servers
}

output "zone_name" {
  value = aws_route53_zone.this.name
}
