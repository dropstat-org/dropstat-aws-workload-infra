# ============================================================
# _modules/aurora
# Aurora Serverless v2 — MySQL 8.0
# Replaces prod db.m5.4xlarge for dev/staging/prod
# ============================================================

module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}

module "aurora" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  version = "~> 9.0"

  name           = var.name
  engine         = "aurora-mysql"
  # When restoring from a snapshot, omit engine_version so Aurora auto-selects
  # the version compatible with the snapshot. Specifying "8.0" resolves to the
  # latest Aurora 8.0 release which may require a newer MySQL minor version than
  # the snapshot's source (e.g. 8.0.44 < required 8.0.45 for aurora 3.10.3).
  engine_version = var.snapshot_identifier == null ? "8.0" : null
  instance_class = "db.serverless"

  instances = {
    writer = {}
  }

  serverlessv2_scaling_configuration = {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  vpc_id               = module.account.vpc.id
  db_subnet_group_name = var.db_subnet_group_name
  create_db_subnet_group = var.db_subnet_group_name == null ? true : false
  subnets              = [for s in module.account.subnets.data : s.id]

  security_group_rules = {
    ecs_ingress = {
      source_security_group_id = var.ecs_security_group_id
      description              = "Allow MySQL from ECS tasks"
    }
  }

  # When restoring from a snapshot, database_name and master_username
  # are inherited from the snapshot — passing them would cause an error.
  database_name   = var.snapshot_identifier == null ? var.database_name   : null
  master_username = var.snapshot_identifier == null ? var.master_username  : null

  snapshot_identifier = var.snapshot_identifier

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
