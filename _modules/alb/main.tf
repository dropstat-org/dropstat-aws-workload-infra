module "alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name     = var.name
  vpc_id   = var.vpc_id
  subnets  = var.private_subnet_ids
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

  listeners = merge(
    {
      http = {
        port     = 80
        protocol = "HTTP"
        # Redirect to HTTPS if certificate provided, otherwise forward to default
        action = var.certificate_arn != null ? {
          type = "redirect"
          redirect = {
            port        = "443"
            protocol    = "HTTPS"
            status_code = "HTTP_301"
          }
        } : {
          type             = "fixed-response"
          fixed_response = {
            content_type = "text/plain"
            message_body = "no route"
            status_code  = "404"
          }
        }
      }
    },
    var.certificate_arn != null ? {
      https = {
        port            = 443
        protocol        = "HTTPS"
        certificate_arn = var.certificate_arn
        action = {
          type             = "fixed-response"
          fixed_response = {
            content_type = "text/plain"
            message_body = "no route"
            status_code  = "404"
          }
        }
      }
    } : {}
  )

  tags = var.tags
}
