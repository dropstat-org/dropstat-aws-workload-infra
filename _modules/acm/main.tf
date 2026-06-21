resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = var.tags
}

# Automatic DNS validation via Route53 — only when zone_id is provided.
# When the domain is registered in Route53, this creates the CNAME records
# and waits for ACM to issue the certificate. No manual steps needed.
resource "aws_route53_record" "validation" {
  for_each = var.zone_id != null ? {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}

  zone_id         = var.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count                   = var.zone_id != null ? 1 : 0
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}

output "acm_certificate_arn" {
  # Depend on validation so downstream resources (API GW) only receive the ARN
  # once the certificate is ISSUED — not while it is still PENDING_VALIDATION.
  value = var.zone_id != null ? aws_acm_certificate_validation.this[0].certificate_arn : aws_acm_certificate.this.arn
}

output "validation_records" {
  description = "DNS records added for validation (reference only — created automatically when zone_id is set)"
  value = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }
}
