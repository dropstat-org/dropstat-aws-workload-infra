# Private Route53 hosted zone for internal service discovery.
# Resolvable only from within the associated VPC — not public.
#
# force_destroy = true allows Terraform to delete all records in the zone
# before destroying it. Required when recreating the zone (e.g. name change).

# Auto-discover the account's VPC by tag convention (same module aurora/ecs use)
# so callers never hardcode a per-account vpc_id. An explicit var.vpc_id still
# wins if provided.
module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}

locals {
  vpc_id = var.vpc_id != "" ? var.vpc_id : module.account.vpc.id
}

resource "aws_route53_zone" "this" {
  name          = var.zone_name
  comment       = var.comment != "" ? var.comment : "Private zone for internal service discovery — ${var.zone_name}"
  force_destroy = var.force_destroy

  vpc {
    vpc_id     = local.vpc_id
    vpc_region = var.vpc_region
  }

  tags = var.tags
}

output "zone_id" {
  description = "Route53 zone ID"
  value       = aws_route53_zone.this.zone_id
}

output "zone_name" {
  description = "Zone name"
  value       = aws_route53_zone.this.name
}

output "name_servers" {
  description = "Name servers (reference only — private zones don't need NS delegation)"
  value       = aws_route53_zone.this.name_servers
}
