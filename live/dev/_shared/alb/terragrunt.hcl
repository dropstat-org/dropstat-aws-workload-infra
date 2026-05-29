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
    vpc_id            = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../_modules/alb"
}

inputs = {
  name              = "dropstat-${local.env.locals.account_name}"
  vpc_id            = dependency.account.outputs.vpc_id
  # ALB goes to public subnets — internet-facing
  public_subnet_ids = dependency.account.outputs.public_subnet_ids
  certificate_arn   = local.env.locals.certificate_arn
}
