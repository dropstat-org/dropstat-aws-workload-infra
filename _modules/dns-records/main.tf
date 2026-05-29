# ============================================================
# _modules/dns-records
# Creates DNS records in the private zone aws.dropstat.internal.
# The zone lives in shared-services — uses aws.dns provider alias
# (cross-account, assumes TerraformCI in shared-services).
# Zone discovery by name — no zone_id needed.
# ============================================================

# Discover the private zone by name — no hardcoded zone_id
data "aws_route53_zone" "private" {
  provider     = aws.dns
  name         = var.zone_name
  private_zone = true
}

module "records" {
  source  = "terraform-aws-modules/route53/aws//modules/records"
  version = "~> 4.0"

  providers = {
    aws = aws.dns
  }

  zone_id = data.aws_route53_zone.private.zone_id

  records = [
    # ALB — all services share one ALB, host-based routing differentiates them
    {
      name    = "alb.${var.env}"
      type    = "CNAME"
      ttl     = 60
      records = [var.alb_dns_name]
    },
    # Aurora cluster endpoint
    {
      name    = "aurora.${var.env}"
      type    = "CNAME"
      ttl     = 60
      records = [var.aurora_endpoint]
    },
    # Per-service aliases — all point to the ALB
    # ALB uses host header to route to the right target group
    {
      name    = "api.${var.env}"
      type    = "CNAME"
      ttl     = 60
      records = [var.alb_dns_name]
    },
    {
      name    = "integrations.${var.env}"
      type    = "CNAME"
      ttl     = 60
      records = [var.alb_dns_name]
    },
    {
      name    = "nursa.${var.env}"
      type    = "CNAME"
      ttl     = 60
      records = [var.alb_dns_name]
    },
  ]
}
