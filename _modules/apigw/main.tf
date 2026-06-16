# ============================================================
# _modules/apigw
# API Gateway HTTP v2 + VPC Link + WAF
# One gateway per environment, routes by hostname to internal ALB.
# VPC Link connects API GW to the internal ALB in private subnets.
# ============================================================

module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}

module "apigw" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "~> 5.0"

  name          = var.name
  description   = "HTTP API for ${var.name}"
  protocol_type = "HTTP"

  # Custom domain — only create when domain_name is provided
  # Module v5 fails with null in replace()/startswith() — guard with create flag
  create_domain_name          = var.domain_name != null
  domain_name                 = var.domain_name != null ? var.domain_name : ""
  domain_name_certificate_arn = var.certificate_arn
  # Route53 record managed separately in dns-records-public to avoid
  # data.aws_route53_zone lookup failures when zone doesn't exist yet.
  create_domain_records = false

  # VPC Link — connects API GW to the internal ALB
  vpc_links = {
    main = {
      name               = "${var.name}-vpc-link"
      subnet_ids         = [for s in module.account.subnets.privates : s.id]
      security_group_ids = [module.sg_vpc_link.security_group_id]
    }
  }

  # In apigateway-v2 module v5, integrations moved inside routes.
  # In apigateway-v2 module v5, key names inside routes.integration changed:
  #   type   (not integration_type)
  #   uri    (not integration_uri)
  #   method (not integration_method)
  routes = {
    for svc_name, svc in var.services : "${svc.method} ${svc.route}" => {
      integration = {
        type            = "HTTP_PROXY"
        method          = svc.method
        uri             = var.alb_listener_arn
        connection_type = "VPC_LINK"
        vpc_link_key    = "main"
        request_parameters = {
          "overwrite:header.host" = svc.hostname
        }
      }
    }
  }

  # Stage — auto-deploy on change
  stage_name = "$default"
  stage_default_route_settings = {
    throttling_burst_limit = var.throttling_burst_limit
    throttling_rate_limit  = var.throttling_rate_limit
  }

  tags = var.tags
}

# ── Security group for VPC Link ───────────────────────────────────────────────
# terraform-aws-modules/security-group — allows API GW to reach internal ALB.
# WAF resources below remain native (no terraform-aws-modules/wafv2 exists in the org).

module "sg_vpc_link" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-vpc-link"
  description = "API Gateway VPC Link - allows egress to internal ALB on 80/443"
  vpc_id      = module.account.vpc.id

  egress_with_cidr_blocks = [
    {
      from_port   = 80
      to_port     = 80
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTP to ALB"
    },
    {
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = "0.0.0.0/0"
      description = "HTTPS to ALB"
    },
  ]

  tags = var.tags
}

# ── WAF — attached to API GW stage ───────────────────────────────────────────

resource "aws_wafv2_web_acl" "this" {
  count = var.waf_enabled ? 1 : 0

  name  = "${var.name}-waf"
  scope = "REGIONAL"  # API GW uses REGIONAL (CloudFront uses CLOUDFRONT)

  default_action {
    allow {}
  }

  # OWASP Top 10
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # Known bad inputs (SQLi, XSS)
  rule {
    name     = "AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # IP reputation list
  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 3
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting per IP
  rule {
    name     = "RateLimitPerIP"
    priority = 4
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = var.tags
}

resource "aws_wafv2_web_acl_association" "this" {
  count = var.waf_enabled ? 1 : 0

  resource_arn = module.apigw.stage_arn
  web_acl_arn  = aws_wafv2_web_acl.this[0].arn
}
