# ============================================================
# _modules/apigw
# API Gateway HTTP v2 + VPC Link + WAF
# One gateway per environment, routes by hostname to internal ALB.
# VPC Link connects API GW to the internal ALB in private subnets.
# ============================================================

module "apigw" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "~> 5.0"

  name          = var.name
  description   = "HTTP API for ${var.name}"
  protocol_type = "HTTP"

  # Custom domain — one per service, all pointing to this gateway
  domain_name                 = var.domain_name
  domain_name_certificate_arn = var.certificate_arn

  # VPC Link — connects API GW to the internal ALB
  vpc_links = {
    main = {
      name               = "${var.name}-vpc-link"
      subnet_ids         = var.private_subnet_ids
      security_group_ids = [module.sg_vpc_link.security_group_id]
    }
  }

  # Integrations — one per service, forwarding to ALB via VPC Link
  integrations = {
    for svc_name, svc in var.services : "${svc.method} ${svc.route}" => {
      integration_type    = "HTTP_PROXY"
      integration_method  = svc.method
      integration_uri     = var.alb_listener_arn
      connection_type     = "VPC_LINK"
      vpc_link            = "main"
      request_parameters  = {
        "overwrite:header.host" = svc.hostname
      }
    }
  }

  # Routes — one per service
  routes = {
    for svc_name, svc in var.services : "${svc.method} ${svc.route}" => {
      integration = "${svc.method} ${svc.route}"
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
  description = "API Gateway VPC Link — allows egress to internal ALB on 80/443"
  vpc_id      = var.vpc_id

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
    override_action { none {} }
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
    override_action { none {} }
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
    override_action { none {} }
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
    action { block {} }
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
