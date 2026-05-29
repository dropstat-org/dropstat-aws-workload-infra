include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
  e      = local.env.locals.account_name  # "dev"
}

dependency "alb" {
  config_path = "../alb"
  mock_outputs = { dns_name = "internal-dropstat-dev-mock.us-east-2.elb.amazonaws.com" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "aurora" {
  config_path = "../../storage/aurora"
  mock_outputs = { cluster_endpoint = "dropstat-dev.cluster-mock.us-east-2.rds.amazonaws.com" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "elasticache" {
  config_path = "../../storage/elasticache"
  mock_outputs = { endpoint = "dropstat-dev.mock.cache.amazonaws.com" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

generate "provider_dns" {
  path      = "_provider_dns.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    provider "aws" {
      alias  = "dns"
      region = "us-east-2"
      assume_role {
        role_arn     = "arn:aws:iam::${local.common.account_ids.shared_services}:role/${local.common.ci.role_name}"
        session_name = "terragrunt-dns-records"
      }
    }
  EOF
}

terraform {
  source = "../../../../_modules/dns-records"
}

inputs = {
  zone_name = local.common.dns.private_zone   # aws.dropstat.internal

  records = [
    # ── ALB (shared by all services — host header does the routing) ──
    {
      name    = "alb.${local.e}"
      type    = "CNAME"
      ttl     = 60
      records = [dependency.alb.outputs.dns_name]
    },
    # ── Per-service aliases (all → ALB) ───────────────────────────────
    {
      name    = "api.${local.e}"
      type    = "CNAME"
      ttl     = 60
      records = [dependency.alb.outputs.dns_name]
    },
    {
      name    = "integrations.${local.e}"
      type    = "CNAME"
      ttl     = 60
      records = [dependency.alb.outputs.dns_name]
    },
    {
      name    = "nursa.${local.e}"
      type    = "CNAME"
      ttl     = 60
      records = [dependency.alb.outputs.dns_name]
    },
    # ── Storage ───────────────────────────────────────────────────────
    {
      name    = "aurora.${local.e}"
      type    = "CNAME"
      ttl     = 60
      records = [dependency.aurora.outputs.cluster_endpoint]
    },
    {
      name    = "redis.${local.e}"
      type    = "CNAME"
      ttl     = 60
      records = [dependency.elasticache.outputs.endpoint]
    },
  ]
}
