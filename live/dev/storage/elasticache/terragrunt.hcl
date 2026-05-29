include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  cfg = local.env.locals.elasticache
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
  source = "../../../../_modules/elasticache"
}

inputs = {
  name = "dropstat-${local.env.locals.account_name}"

  # ElastiCache → data subnets (same layer as Aurora)
  vpc_id     = dependency.account.outputs.vpc_id
  subnet_ids = dependency.account.outputs.data_subnet_ids

  ecs_security_group_id    = "sg-00000000000000000"  # TODO: replace after first ECS deploy
  node_type                = local.cfg.node_type
  num_cache_nodes          = local.cfg.num_cache_nodes
  snapshot_retention_limit = 0  # no backups for dev
}
