include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
  cfg    = local.env.locals.ecs.integrations_rest
}

dependency "account" {
  config_path = "../../_shared/account-data"
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../_modules/ecs-service"
}

inputs = {
  name   = "integrations-rest-${local.env.locals.account_name}"
  cpu    = local.cfg.cpu
  memory = local.cfg.memory
  image  = "${local.common.ecr_registry}/${local.common.ecr_repos.integrations_rest}:${local.env.locals.image_tags.integrations_rest}"

  container_port    = 8000
  health_check_path = "/health"
  desired_count        = local.cfg.desired_count
  min_task_count       = local.cfg.min_task_count
  max_task_count       = local.cfg.max_task_count
  scaling_target_value = local.cfg.scaling_target_value

  # ECS → private subnets (workload layer)
  vpc_id             = dependency.account.outputs.vpc_id
  private_subnet_ids = dependency.account.outputs.private_subnet_ids

  environment_vars = [
    { name = "LOG_LEVEL", value = "INFO" },
  ]

  secrets = [
    { name = "KNIT_WEBHOOK_SECRET", valueFrom = "arn:aws:secretsmanager:us-east-2:${local.env.locals.account_id}:secret:dropstat/${local.env.locals.account_name}/integrations-rest/knit" },
  ]

  ssm_param_arns = []
  secret_arns = [
    "arn:aws:secretsmanager:us-east-2:${local.env.locals.account_id}:secret:dropstat/${local.env.locals.account_name}/integrations-rest/*"
  ]

  log_retention_days = local.env.locals.log_retention_days
}
