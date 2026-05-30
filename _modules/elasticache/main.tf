# ============================================================
# _modules/elasticache
# Redis — replaces Redis sidecar in ECS task definitions
# ============================================================

module "elasticache" {
  source  = "terraform-aws-modules/elasticache/aws"
  version = "~> 1.0"

  cluster_id               = var.name
  create_replication_group = false

  engine          = "redis"
  engine_version  = "7.1"
  node_type       = var.node_type
  num_cache_nodes = var.num_cache_nodes
  port            = 6379

  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  security_group_rules = {
    ecs_ingress = {
      referenced_security_group_id = var.ecs_security_group_id
      description                  = "Allow Redis from ECS tasks"
    }
  }

  apply_immediately          = true
  auto_minor_version_upgrade = true

  # Backups — disable for dev, enable for prod
  snapshot_retention_limit = var.snapshot_retention_limit

  tags = var.tags
}
