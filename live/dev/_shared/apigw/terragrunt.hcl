include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
}

dependency "account" {
  config_path = "../account-data"
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "alb" {
  config_path = "../alb"
  mock_outputs = {
    http_listener_arn  = "arn:aws:elasticloadbalancing:us-east-2:453531893227:listener/app/mock/abc/def"
    https_listener_arn = null
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../_modules/apigw"
}

locals {
  # Use HTTPS listener if certificate is configured, otherwise HTTP
  listener_arn = dependency.alb.outputs.https_listener_arn != null ? dependency.alb.outputs.https_listener_arn : dependency.alb.outputs.http_listener_arn
}

inputs = {
  name               = "dropstat-${local.env.locals.account_name}"
  vpc_id             = dependency.account.outputs.vpc_id
  private_subnet_ids = dependency.account.outputs.private_subnet_ids
  alb_listener_arn   = local.listener_arn

  domain_name     = local.env.locals.apigw.domain_name
  certificate_arn = local.env.locals.certificate_arn

  # Routes — each service gets its own path prefix
  # API GW sends the correct host header to ALB for host-based routing
  services = {
    dropstat_api = {
      method   = "ANY"
      route    = "/api/{proxy+}"
      hostname = local.env.locals.ecs.dropstat_api.hostnames[0]
    }
    integrations_rest = {
      method   = "ANY"
      route    = "/integrations/{proxy+}"
      hostname = local.env.locals.ecs.integrations_rest.hostnames[0]
    }
    nursa = {
      method   = "ANY"
      route    = "/nursa/{proxy+}"
      hostname = local.env.locals.ecs.nursa.hostnames[0]
    }
  }

  throttling_burst_limit = local.env.locals.apigw.throttling_burst_limit
  throttling_rate_limit  = local.env.locals.apigw.throttling_rate_limit
  waf_enabled            = local.env.locals.apigw.waf_enabled
  waf_rate_limit         = local.env.locals.apigw.waf_rate_limit
}
