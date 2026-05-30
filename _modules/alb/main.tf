module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}

module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name     = var.name
  vpc_id   = module.account.vpc.id
  subnets  = [for s in module.account.subnets.privates : s.id]
  internal = true  # not internet-facing — API GW connects via VPC Link

  # Security group — allow HTTP/HTTPS inbound from internet
  security_group_ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
    https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  # ALB module v9: action type is a top-level key on the listener object,
  # not nested under "action". Use redirect/fixed_response/forward directly.
  listeners = merge(
    {
      http = merge(
        { port = 80, protocol = "HTTP" },
        var.certificate_arn != null ? {
          redirect = {
            port        = "443"
            protocol    = "HTTPS"
            status_code = "HTTP_301"
          }
        } : {
          fixed_response = {
            content_type = "text/plain"
            message_body = "no route"
            status_code  = "404"
          }
        }
      )
    },
    var.certificate_arn != null ? {
      https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = var.certificate_arn
        fixed_response = {
          content_type = "text/plain"
          message_body = "no route"
          status_code  = "404"
        }
      }
    } : {}
  )

  tags = var.tags
}
