# ============================================================
# _modules/ecs-service
# ECS Fargate service + target group + ALB listener rule + auto-scaling
# ALB and cluster are created separately and passed in.
# ============================================================

locals {
  listener_arn = var.https_listener_arn != null ? var.https_listener_arn : var.http_listener_arn
}

# ── Target group ──────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "this" {
  name        = var.name
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200-299"
  }

  # Allow draining before scale-in removes a task
  deregistration_delay = 30

  tags = var.tags
}

# ── ALB listener rule — host-based routing ────────────────────────────────────

resource "aws_lb_listener_rule" "this" {
  listener_arn = local.listener_arn
  priority     = var.listener_rule_priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  condition {
    host_header {
      values = var.hostnames
    }
  }

  tags = var.tags
}

# ── Security group for ECS tasks ──────────────────────────────────────────────
# terraform-aws-modules/security-group — no loose aws_security_group resources.
# AppAutoScaling resources below remain native (no terraform-aws-modules equivalent).

module "sg_tasks" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-tasks"
  description = "ECS tasks for ${var.name} — inbound from ALB only"
  vpc_id      = var.vpc_id

  ingress_with_source_security_group_id = [
    {
      from_port                = var.container_port
      to_port                  = var.container_port
      protocol                 = "tcp"
      source_security_group_id = var.alb_security_group_id
      description              = "Allow inbound from ALB"
    }
  ]

  egress_rules = ["all-all"]

  tags = var.tags
}

# ── ECS service ───────────────────────────────────────────────────────────────

module "service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 6.0"

  name        = var.name
  cluster_arn = var.cluster_arn

  cpu    = var.cpu
  memory = var.memory

  desired_count                  = var.desired_count
  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  container_definitions = {
    (var.name) = {
      image     = var.image
      cpu       = var.cpu
      memory    = var.memory
      essential = true

      port_mappings = [{
        containerPort = var.container_port
        protocol      = "tcp"
      }]

      environment = var.environment_vars
      secrets     = var.secrets

      log_configuration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = "/ecs/${var.name}"
          awslogs-region        = "us-east-2"
          awslogs-stream-prefix = "ecs"
        }
      }

      readonly_root_filesystem               = false
      cloudwatch_log_group_retention_in_days = var.log_retention_days
    }
  }

  # Networking
  subnet_ids            = var.private_subnet_ids
  security_group_ids    = [module.sg_tasks.security_group_id]
  create_security_group = false

  # Load balancer
  load_balancer = {
    service = {
      target_group_arn = aws_lb_target_group.this.arn
      container_name   = var.name
      container_port   = var.container_port
    }
  }

  # IAM
  task_exec_ssm_param_arns  = var.ssm_param_arns
  task_exec_secret_arns     = var.secret_arns
  # ECS module v6: tasks_iam_role_statements is list(object), not map.
  # Convert map { key = {effect,actions,resources} } → list of statement objects.
  tasks_iam_role_statements = [for k, v in var.task_iam_statements : v]

  # ── Auto-scaling — built-in via terraform-aws-modules/ecs service module ──
  # aws_appautoscaling_target + aws_appautoscaling_policy replaced by module.
  # ALBRequestCountPerTarget requires resource_label = alb_arn_suffix/tg_arn_suffix.
  enable_autoscaling       = true
  autoscaling_min_capacity = var.min_task_count
  autoscaling_max_capacity = var.max_task_count

  autoscaling_policies = {
    alb_requests = {
      policy_type = "TargetTrackingScaling"
      target_tracking_scaling_policy_configuration = {
        target_value       = var.scaling_target_value
        scale_in_cooldown  = 300
        scale_out_cooldown = 60
        disable_scale_in   = false
        predefined_metric_specification = {
          predefined_metric_type = "ALBRequestCountPerTarget"
          resource_label         = "${var.alb_arn_suffix}/${aws_lb_target_group.this.arn_suffix}"
        }
      }
    }
  }

  tags = var.tags
}
