# ============================================================
# _modules/elasticache
# Redis — VPC and subnets discovered via tm-aws-account-data
# ============================================================

module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}

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

  vpc_id     = module.account.vpc.id
  subnet_ids = module.account.subnets.privates[*].id

  security_group_rules = {
    vpc_internal = {
      # aws_vpc_security_group_ingress_rule requires a single cidr_ipv4.
      # Use the VPC CIDR — covers all private subnets without needing per-subnet rules.
      cidr_ipv4   = module.account.vpc.cidr_block
      description = "Allow Redis from VPC (private subnets only)"
    }
  }

  apply_immediately          = true
  auto_minor_version_upgrade = true

  snapshot_retention_limit = var.snapshot_retention_limit

  tags = var.tags
}
