output "arn"            { value = module.alb.arn }
output "arn_suffix"     { value = module.alb.arn_suffix }
output "dns_name"       { value = module.alb.dns_name }
output "zone_id"        { value = module.alb.zone_id }
output "security_group_id" { value = module.alb.security_group_id }

# Listener ARNs — used by ecs-service to attach listener rules
output "http_listener_arn"  { value = try(module.alb.listeners["http"].arn, null) }
output "https_listener_arn" { value = try(module.alb.listeners["https"].arn, null) }
