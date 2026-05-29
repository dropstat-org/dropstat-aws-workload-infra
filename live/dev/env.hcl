locals {
  account_name = "dev"
  account_id   = "453531893227"
  role_arn     = "arn:aws:iam::453531893227:role/TerraformCI"
  region       = "us-east-2"

  log_retention_days = 7

  ecs = {
    dropstat_api = {
      cpu                  = 1024
      memory               = 2048
      desired_count        = 1
      min_task_count       = 0
      max_task_count       = 3
      scaling_target_value = 10   # req/target/min — scales to 0 when idle
    }
    integrations_rest = {
      cpu                  = 256
      memory               = 512
      desired_count        = 1
      min_task_count       = 0
      max_task_count       = 2
      scaling_target_value = 10
    }
    nursa = {
      cpu                  = 1024
      memory               = 2048
      desired_count        = 1
      min_task_count       = 0
      max_task_count       = 3
      scaling_target_value = 10
    }
  }

  aurora = {
    min_capacity                 = 0.5
    max_capacity                 = 2.0
    skip_final_snapshot          = true
    deletion_protection          = false
    monitoring_interval          = 0
    performance_insights_enabled = false
  }

  elasticache = {
    node_type       = "cache.t4g.micro"
    num_cache_nodes = 1
  }

  mq = {
    instance_type       = "mq.t3.micro"
    publicly_accessible = false
  }

  queue_suffix = "-dev"

  # Image tags — overridden by CI/CD pipeline via TF_VAR or terragrunt inputs
  image_tags = {
    dropstat_api      = "latest"
    integrations_rest = "latest"
    nursa             = "latest"
  }
}
