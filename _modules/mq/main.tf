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
  security_groups    = [module.sg_mq.security_group_id]

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

# ── Security group for Amazon MQ ─────────────────────────────────────────────
# terraform-aws-modules/security-group — no loose aws_security_group resources.
# aws_mq_broker stays native (no terraform-aws-modules/mq exists).

module "sg_mq" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-mq"
  description = "Amazon MQ — allow MQTT, AMQPS and Web Console from ECS"
  vpc_id      = var.vpc_id

  ingress_with_source_security_group_id = flatten([
    for sg_id in var.allowed_security_group_ids : [
      {
        from_port                = 1883
        to_port                  = 1883
        protocol                 = "tcp"
        source_security_group_id = sg_id
        description              = "MQTT"
      },
      {
        from_port                = 5671
        to_port                  = 5671
        protocol                 = "tcp"
        source_security_group_id = sg_id
        description              = "AMQPS"
      },
      {
        from_port                = 8162
        to_port                  = 8162
        protocol                 = "tcp"
        source_security_group_id = sg_id
        description              = "ActiveMQ Web Console"
      },
    ]
  ])

  egress_rules = ["all-all"]

  tags = merge(var.tags, { Name = "${var.name}-mq" })
}
