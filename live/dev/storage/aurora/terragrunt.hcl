include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
  cfg    = local.env.locals.aurora
}

dependency "account" {
  config_path = "../../_shared/account-data"
  mock_outputs = {
    vpc_id         = "vpc-00000000000000000"
    data_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../_modules/aurora"
}

inputs = {
  name = "dropstat-${local.env.locals.account_name}"

  # Aurora → data subnets (no internet route, isolated from ECS)
  vpc_id     = dependency.account.outputs.vpc_id
  subnet_ids = dependency.account.outputs.data_subnet_ids

  ecs_security_group_id = "sg-00000000000000000"  # TODO: replace after first ECS deploy

  database_name   = "dropstat"
  master_username = "appuser"

  min_capacity = local.cfg.min_capacity
  max_capacity = local.cfg.max_capacity

  skip_final_snapshot          = local.cfg.skip_final_snapshot
  deletion_protection          = local.cfg.deletion_protection
  monitoring_interval          = local.cfg.monitoring_interval
  performance_insights_enabled = local.cfg.performance_insights_enabled
  backup_retention_period      = 7
}
