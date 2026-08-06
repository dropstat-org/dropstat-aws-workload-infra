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

  # Custom domain — only create when domain_name is provided AND we have a valid
  # ACM cert ARN. During a two-phase env bootstrap the cert ARN is a "FILL_*"
  # placeholder until ACM issues it; can(regex) keeps the plan green until then
  # (the domain appears once the real ARN is filled). Real ARNs are unaffected.
  # Module v5 also fails with null in replace()/startswith() — guard with the flag.
  create_domain_name          = var.domain_name != null && can(regex("^arn:aws:", var.certificate_arn))
  domain_name                 = var.domain_name != null ? var.domain_name : ""
  domain_name_certificate_arn = var.certificate_arn
  # We bring our own ACM cert — disable the module's internal cert creation so it
  # uses domain_name_certificate_arn instead of module.acm.acm_certificate_arn.
  create_certificate = false
  # Route53 record managed separately in dns-records-public to avoid
  # data.aws_route53_zone lookup failures when zone doesn't exist yet.
  create_domain_records = false

  # CORS — el HTTP API responde el preflight (OPTIONS) y agrega los headers en
  # las respuestas. Sin esto, los frontends (CloudFront, otro origen) mueren en
  # "blocked by CORS policy: No 'Access-Control-Allow-Origin'". Cuando se
  # configura aqui, API GW tiene precedencia sobre headers CORS del backend.
  #
  # Precedencia significa REEMPLAZO, no merge: los headers CORS que manda el
  # backend se descartan enteros. Por eso expose_headers tiene que declararse
  # aqui aunque Spring ya lo mande. Se omitio al principio y el navegador dejo
  # de ver Content-Disposition en qa: la descarga llegaba completa pero con el
  # nombre generico, porque el JS no puede leer un header que no esta expuesto.
  cors_configuration = length(var.cors_allowed_origins) > 0 ? {
    allow_origins  = var.cors_allowed_origins
    allow_methods  = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
    allow_headers  = ["*"]
    expose_headers = var.cors_expose_headers
    max_age        = 3600
  } : null

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
