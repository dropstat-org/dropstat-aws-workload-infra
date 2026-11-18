ephemeral "random_password" "db_user" {
  for_each = var.db_users
  length   = var.password_length
  special  = false
}

resource "aws_secretsmanager_secret" "db_user" {
  for_each                = var.db_users
  name                    = each.value.secret_name
  description             = each.value.description
  recovery_window_in_days = var.recovery_window_in_days
  tags                    = merge(var.tags, { Name = each.value.secret_name })
}

resource "aws_secretsmanager_secret_version" "db_user" {
  for_each  = var.db_users
  secret_id = aws_secretsmanager_secret.db_user[each.key].id

  secret_string_wo = jsonencode({
    engine   = "mysql"
    host     = var.db_host
    port     = var.db_port
    dbname   = var.db_name
    username = each.value.username
    password = ephemeral.random_password.db_user[each.key].result
  })
  secret_string_wo_version = each.value.version
}

resource "aws_secretsmanager_secret" "static" {
  for_each                = var.static_secrets
  name                    = each.value.secret_name
  description             = each.value.description
  recovery_window_in_days = var.recovery_window_in_days
  tags                    = merge(var.tags, { Name = each.value.secret_name })
}

resource "aws_secretsmanager_secret_version" "static" {
  for_each                 = var.static_secrets
  secret_id                = aws_secretsmanager_secret.static[each.key].id
  secret_string_wo         = jsonencode({ for key in each.value.keys : key => "REPLACE_ME" })
  secret_string_wo_version = each.value.version
}
