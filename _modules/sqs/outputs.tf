output "queue_urls" {
  value = { for k, v in module.queues : k => v.queue_url }
}
output "queue_arns" {
  value = { for k, v in module.queues : k => v.queue_arn }
}
