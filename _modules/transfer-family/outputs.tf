output "server_id" {
  description = "Transfer Family server ID — used as prefix for user secrets: {server_id}/{username}"
  value       = aws_transfer_server.this.id
}

output "server_endpoint" {
  description = "Default SFTP endpoint (use custom hostname if configured)"
  value       = aws_transfer_server.this.endpoint
}

output "s3_bucket_name" {
  description = "S3 bucket name for SFTP home directories"
  value       = aws_s3_bucket.sftp.id
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.sftp.arn
}

output "user_role_arn" {
  description = "IAM role ARN to put in each user secret under 'Role'"
  value       = aws_iam_role.sftp_user.arn
}
