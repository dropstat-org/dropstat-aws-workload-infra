include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
  cfg    = local.env.locals.ecs.nursa
}

dependency "account" {
  config_path = "../../_shared/account-data"
  mock_outputs = {
    vpc_id             = "vpc-00000000000000000"
    private_subnet_ids = ["subnet-00000000000000001", "subnet-00000000000000002"]
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "aurora" {
  config_path = "../../storage/aurora"
  mock_outputs = { cluster_endpoint = "mock.cluster.us-east-2.rds.amazonaws.com" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../_modules/ecs-service"
}

inputs = {
  name   = "nursa-${local.env.locals.account_name}"
  cpu    = local.cfg.cpu
  memory = local.cfg.memory
  image  = "${local.common.ecr_registry}/${local.common.ecr_repos.nursa}:${local.env.locals.image_tags.nursa}"

  container_port    = 8081
  health_check_path = "/api/version"
  desired_count        = local.cfg.desired_count
  min_task_count       = local.cfg.min_task_count
  max_task_count       = local.cfg.max_task_count
  scaling_target_value = local.cfg.scaling_target_value

  # ECS → private subnets (workload layer)
  vpc_id             = dependency.account.outputs.vpc_id
  private_subnet_ids = dependency.account.outputs.private_subnet_ids

  environment_vars = [
    { name = "AGENCY_NAME",             value = "Nursa" },
    { name = "AGENCY_MASTER_ID",        value = "53" },
    { name = "PUBLIC_APPLICATION_HOST", value = "https://nursa-${local.env.locals.account_name}.api2.dropstat.com" },
    { name = "SQS_QUEUE_ENABLED",       value = "true" },
    { name = "SQS_QUEUE_NAME",          value = "shifts-queue-${local.env.locals.account_name}" },
    { name = "DROPSTAT_API_BASE",       value = "http://dropstat-api-${local.env.locals.account_name}.internal/dropstat/api/" },
    { name = "IS_WEBHOOK_DEBUG_MODE",   value = local.env.locals.account_name == "dev" ? "true" : "false" },
  ]

  secrets = [
    { name = "DROPSTAT_PASSWORD",  valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/NURSA_DROPSTAT_PASSWORD" },
    { name = "DROPSTAT_USER_NAME", valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/NURSA_DROPSTAT_USER" },
    { name = "NURSA_CLIENT_ID",    valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/NURSA_CLIENT_ID" },
    { name = "NURSA_CLIENT_SECRET", valueFrom = "arn:aws:secretsmanager:us-east-2:${local.env.locals.account_id}:secret:dropstat/${local.env.locals.account_name}/nursa/client-secret" },
    { name = "NURSA_USER_NAME",    valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/NURSA_USER_NAME" },
    { name = "NURSA_PASSWORD",     valueFrom = "arn:aws:secretsmanager:us-east-2:${local.env.locals.account_id}:secret:dropstat/${local.env.locals.account_name}/nursa/password" },
  ]

  ssm_param_arns = [
    "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/*"
  ]
  secret_arns = [
    "arn:aws:secretsmanager:us-east-2:${local.env.locals.account_id}:secret:dropstat/${local.env.locals.account_name}/nursa/*"
  ]

  task_iam_statements = {
    sqs = {
      effect    = "Allow"
      actions   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      resources = ["arn:aws:sqs:us-east-2:${local.env.locals.account_id}:shifts-queue-${local.env.locals.account_name}"]
    }
  }

  log_retention_days = local.env.locals.log_retention_days
}
