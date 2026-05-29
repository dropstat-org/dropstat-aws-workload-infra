output "endpoint"          { value = module.elasticache.cluster_cache_nodes[0].address }
output "port"              { value = 6379 }
output "security_group_id" { value = module.elasticache.security_group_id }
