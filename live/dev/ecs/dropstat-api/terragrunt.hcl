include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
  cfg    = local.env.locals.ecs.dropstat_api
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
  mock_outputs = {
    cluster_endpoint       = "mock.cluster.us-east-2.rds.amazonaws.com"
    master_user_secret_arn = "arn:aws:secretsmanager:us-east-2:453531893227:secret:mock"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "elasticache" {
  config_path = "../../storage/elasticache"
  mock_outputs = { endpoint = "mock.cache.amazonaws.com" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "mq" {
  config_path = "../../messaging/mq"
  mock_outputs = { mqtt_endpoint = "ssl://mock.mq.amazonaws.com:8883" }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

terraform {
  source = "../../../../_modules/ecs-service"
}

inputs = {
  name   = "dropstat-api-${local.env.locals.account_name}"
  cpu    = local.cfg.cpu
  memory = local.cfg.memory
  image  = "${local.common.ecr_registry}/${local.common.ecr_repos.dropstat_api}:${local.env.locals.image_tags.dropstat_api}"

  container_port    = 8080
  health_check_path = "/actuator/health"
  desired_count        = local.cfg.desired_count
  min_task_count       = local.cfg.min_task_count
  max_task_count       = local.cfg.max_task_count
  scaling_target_value = local.cfg.scaling_target_value

  # ECS → private subnets (workload layer)
  vpc_id             = dependency.account.outputs.vpc_id
  private_subnet_ids = dependency.account.outputs.private_subnet_ids

  environment_vars = [
    { name = "AWS_REGION",          value = "us-east-2" },
    { name = "CURRENT_ENVIRONMENT", value = upper(local.env.locals.account_name) },
    { name = "SPRING_JPA_SHOW_SQL", value = "false" },
    { name = "LOGGING_LEVEL_ROOT",  value = "info" },
    { name = "SQS_ENABLED",         value = "true" },
    { name = "SQS_SHIFTS_QUEUE",    value = "shifts-queue-${local.env.locals.account_name}" },
    { name = "SQS_SMS_QUEUE",       value = "staff-shift-sms-queue-${local.env.locals.account_name}" },
    { name = "SQS_FTP_QUEUE",       value = "ftp-transfer-queue-${local.env.locals.account_name}" },
    { name = "MQTT_HOSTNAME",       value = dependency.mq.outputs.mqtt_endpoint },
    { name = "REDIS_HOST",          value = dependency.elasticache.outputs.endpoint },
  ]

  secrets = [
    { name = "DATABASE_URL",   valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/DATABASE_URL" },
    { name = "USERNAME",       valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/DB_USERNAME" },
    { name = "PASSWORD",       valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/DB_PASSWORD" },
    { name = "JWT_SECRET_KEY", valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/JWT_SECRET_KEY" },
    { name = "MQTT_PASSWORD",  valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/MQTT_PASSWORD" },
    { name = "MQTT_USERNAME",  valueFrom = "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/MQTT_USERNAME" },
  ]

  ssm_param_arns = [
    "arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/*"
  ]

  secret_arns = [
    dependency.aurora.outputs.master_user_secret_arn
  ]

  task_iam_statements = {
    sqs = {
      effect    = "Allow"
      actions   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
      resources = ["arn:aws:sqs:us-east-2:${local.env.locals.account_id}:*-${local.env.locals.account_name}"]
    }
    ssm = {
      effect    = "Allow"
      actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
      resources = ["arn:aws:ssm:us-east-2:${local.env.locals.account_id}:parameter/dropstat/${local.env.locals.account_name}/*"]
    }
  }

  log_retention_days = local.env.locals.log_retention_days
}
