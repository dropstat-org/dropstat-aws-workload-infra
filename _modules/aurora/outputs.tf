output "cluster_endpoint"          { value = module.aurora.cluster_endpoint }
output "cluster_reader_endpoint"   { value = module.aurora.cluster_reader_endpoint }
output "cluster_id"                { value = module.aurora.cluster_id }
output "master_user_secret_arn"    { value = module.aurora.cluster_master_user_secret[0].secret_arn }
output "security_group_id"         { value = module.aurora.security_group_id }
