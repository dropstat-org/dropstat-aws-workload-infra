# ECS module v6: service ARN is output "id", not "arn"
output "service_arn"       { value = module.service.id }
output "service_name"      { value = module.service.name }
output "security_group_id" { value = module.sg_tasks.security_group_id }
output "target_group_arn"  { value = aws_lb_target_group.this.arn }
output "task_role_arn"     { value = module.service.tasks_iam_role_arn }
