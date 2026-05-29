# Exposes VPC and subnet IDs for the current account.
# Uses tm-aws-account-data — discovers VPC and subnets by tag, no remote state needed.
# Consumed via dependency {} by all live/dev/* modules.

module "config" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=v1.0.0"
}

output "vpc_id" {
  value = module.config.vpc.id
}

output "public_subnet_ids" {
  description = "Public subnets — ALB"
  value       = [for s in module.config.subnets.publics : s.id]
}

output "private_subnet_ids" {
  description = "Workload subnets — ECS tasks, Lambda"
  value       = [for s in module.config.subnets.privates : s.id]
}

output "data_subnet_ids" {
  description = "Data subnets — Aurora, ElastiCache"
  value       = [for s in module.config.subnets.data : s.id]
}

output "account" {
  value = module.config.account
}
