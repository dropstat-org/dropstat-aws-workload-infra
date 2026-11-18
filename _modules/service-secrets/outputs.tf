output "db_user_secret_arns" {
  value = { for key, secret in aws_secretsmanager_secret.db_user : key => secret.arn }
}

output "static_secret_arns" {
  value = { for key, secret in aws_secretsmanager_secret.static : key => secret.arn }
}

output "all_secret_arns" {
  value = concat(
    [for secret in aws_secretsmanager_secret.db_user : secret.arn],
    [for secret in aws_secretsmanager_secret.static : secret.arn]
  )
}
