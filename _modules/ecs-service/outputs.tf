output "service_arn"       { value = module.service.arn }
output "service_name"      { value = module.service.name }
output "security_group_id" { value = aws_security_group.tasks.id }
output "target_group_arn"  { value = aws_lb_target_group.this.arn }
output "task_role_arn"     { value = module.service.tasks_iam_role_arn }
