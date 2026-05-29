output "broker_id"       { value = aws_mq_broker.this.id }
output "broker_arn"      { value = aws_mq_broker.this.arn }
output "mqtt_endpoint" {
  value = "ssl://${aws_mq_broker.this.instances[0].endpoints[0]}"
}
output "console_url" {
  value = aws_mq_broker.this.instances[0].console_url
}
output "security_group_id" { value = aws_security_group.mq.id }
