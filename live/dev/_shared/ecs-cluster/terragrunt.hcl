include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
}

terraform {
  source = "../../../../_modules/ecs-cluster"
}

inputs = {
  name                       = "dropstat-${local.env.locals.account_name}"
  container_insights_enabled = local.env.locals.container_insights_enabled
}
