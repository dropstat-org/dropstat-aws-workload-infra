# ============================================================
# _modules/mq
# Amazon MQ (ActiveMQ) — no terraform-aws-modules equivalent
# Native resources used directly
# ============================================================

resource "aws_mq_broker" "this" {
  broker_name         = var.name
  engine_type         = "ACTIVEMQ"
  engine_version      = var.engine_version
  host_instance_type  = var.instance_type
  deployment_mode     = "SINGLE_INSTANCE"
  publicly_accessible = var.publicly_accessible

  subnet_ids         = var.publicly_accessible ? null : [var.subnet_ids[0]]
  security_groups    = [aws_security_group.mq.id]

  user {
    username = var.admin_username
    password = var.admin_password
  }

  logs {
    general = true
    audit   = false
  }

  maintenance_window_start_time {
    day_of_week = "SUNDAY"
    time_of_day = "06:00"
    time_zone   = "UTC"
  }

  tags = var.tags
}

resource "aws_security_group" "mq" {
  name        = "${var.name}-mq"
  description = "Amazon MQ — allow MQTT and AMQPS from ECS"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 1883
    to_port         = 1883
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    description     = "MQTT"
  }

  ingress {
    from_port       = 5671
    to_port         = 5671
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    description     = "AMQPS"
  }

  ingress {
    from_port       = 8162
    to_port         = 8162
    protocol        = "tcp"
    security_groups = var.allowed_security_group_ids
    description     = "ActiveMQ Web Console"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-mq" })
}
