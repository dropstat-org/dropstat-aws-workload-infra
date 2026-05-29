include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  cfg = local.env.locals.mq
}

dependency "account" {
  config_path = "../../../_shared/account-data"
  mock_outputs = {
    vpc_id              = "vpc-00000000000000000"
    private_subnet_ids  = ["subnet-00000000000000001", "subnet-00000000000000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../_modules/mq"
}

inputs = {
  name          = "dropstat-${local.env.locals.account_name}"

  # MQ → private subnets (same layer as ECS)
  vpc_id     = dependency.account.outputs.vpc_id
  subnet_ids = dependency.account.outputs.private_subnet_ids

  instance_type              = local.cfg.instance_type
  publicly_accessible        = local.cfg.publicly_accessible
  allowed_security_group_ids = []  # TODO: add ECS SG after first ECS deploy

  admin_username = "dropstat"
  # Set via: aws ssm put-parameter --name /dropstat/dev/MQ_ADMIN_PASSWORD --value "..." --type SecureString
  admin_password = "REPLACE_BEFORE_APPLY"
}
