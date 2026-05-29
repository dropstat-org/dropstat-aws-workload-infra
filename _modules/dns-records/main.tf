data "aws_route53_zone" "private" {
  provider     = aws.dns
  name         = var.zone_name
  private_zone = true
}

module "records" {
  source  = "terraform-aws-modules/route53/aws//modules/records"
  version = "~> 4.0"

  providers = { aws = aws.dns }

  zone_id = data.aws_route53_zone.private.zone_id
  records = var.records
}
