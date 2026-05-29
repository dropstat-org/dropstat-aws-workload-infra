# ============================================================
# _modules/ecs-service
# Wraps terraform-aws-modules/ecs express-service
# Used by: live/{env}/ecs/{service}/
# ============================================================

module "service" {
  source  = "terraform-aws-modules/ecs/aws//modules/express-service"
  version = "~> 5.12"

  name = var.name

  # Compute
  cpu    = var.cpu
  memory = var.memory

  # Container
  primary_container = {
    image            = var.image
    container_port   = var.container_port
    health_check_path = var.health_check_path

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
  }

  # Networking
  vpc_id = var.vpc_id
  network_configuration = {
    subnets = var.private_subnet_ids
  }

  # Security group — allow outbound only; inbound managed by ALB in express-service
  security_group_egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  # Auto-scaling
  scaling_target = {
    metric_type     = "ECSServiceAverageCPUUtilization"
    target_value    = 70
    min_task_count  = var.desired_count
    max_task_count  = var.desired_count * 3
  }

  # IAM — grant access to SSM parameters and Secrets Manager
  execution_ssm_param_arns = var.ssm_param_arns
  execution_secret_arns    = var.secret_arns

  # Task role — custom statements (e.g. SQS, S3 access)
  task_iam_role_statements = var.task_iam_statements

  # CloudWatch logs
  cloudwatch_log_group_retention_in_days = var.log_retention_days

  tags = var.tags
}
