include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
}

dependency "alb" {
  config_path = "../alb"
  mock_outputs = {
    dns_name = "internal-dropstat-dev-mock.us-east-2.elb.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "aurora" {
  config_path = "../../storage/aurora"
  mock_outputs = {
    cluster_endpoint = "dropstat-dev.cluster-mock.us-east-2.rds.amazonaws.com"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# ── Cross-account provider ─────────────────────────────────────────────────
# Route 53 zone lives in shared-services (944884337673).
# aws.dns provider assumes TerraformCI there to write records.

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
  zone_name       = local.common.dns.private_zone
  env             = local.env.locals.account_name
  alb_dns_name    = dependency.alb.outputs.dns_name
  aurora_endpoint = dependency.aurora.outputs.cluster_endpoint
}
