# ============================================================
# _modules/aurora
# Aurora Serverless v2 — MySQL 8.0
# Replaces prod db.m5.4xlarge for dev/staging/prod
# ============================================================

module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0"

  name            = var.name
  engine          = "aurora-mysql"
  engine_version  = "8.0"
  instance_class  = "db.serverless"

  instances = {
    writer = {}
  }

  serverlessv2_scaling_configuration = {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  vpc_id               = var.vpc_id
  db_subnet_group_name = var.db_subnet_group_name
  create_db_subnet_group = var.db_subnet_group_name == null ? true : false
  subnets              = var.subnet_ids

  security_group_rules = {
    ecs_ingress = {
      referenced_security_group_id = var.ecs_security_group_id
      description                  = "Allow MySQL from ECS tasks"
    }
  }

  database_name   = var.database_name
  master_username = var.master_username

  storage_encrypted   = true
  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection

  # Enable enhanced monitoring + Performance Insights in prod
  monitoring_interval             = var.monitoring_interval
  performance_insights_enabled    = var.performance_insights_enabled

  # Backup
  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "07:00-08:00"

  # Store master password in Secrets Manager automatically
  manage_master_user_password = true

  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = var.tags
}
