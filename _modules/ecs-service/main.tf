# ============================================================
# _modules/ecs-service
# ECS Fargate service + target group + ALB listener rule + auto-scaling
#
# The aws_ecs_task_definition is managed DIRECTLY (not via the ECS service
# module's container_definitions handling) because the service module v6.12
# does not correctly forward port_mappings to the container-definition
# submodule. Using jsonencode() guarantees portMappings is always present.
# ============================================================

module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}

locals {
  listener_arn = var.https_listener_arn != null ? var.https_listener_arn : var.http_listener_arn
}

# ── Image ownership: CD pipeline is the source of truth for the image ─────────
#
# workload-deploy manages infra (env vars, IAM, sizing, networking).
# App CD pipelines own the image tag (push new image → register task def → deploy).
#
# To prevent workload-deploy from reverting an image deployed by a CD pipeline,
# we read the task definition ARN currently active on the ECS service.
# If the service exists, we pass that ARN to the ECS service module — Terraform
# never changes which revision is live. On first deploy (service doesn't exist),
# we fall back to the task def we create below.
data "external" "active_task_definition" {
  program = ["bash", "-c", <<-EOT
    ARN=$(aws ecs describe-services \
      --cluster "${var.cluster_name}" \
      --services "${var.name}" \
      --region us-east-2 \
      --query 'services[0].taskDefinition' \
      --output text 2>/dev/null)
    if [ -z "$ARN" ] || [ "$ARN" = "None" ] || [ "$ARN" = "null" ]; then
      printf '{"arn":""}'
    else
      printf '{"arn":"%s"}' "$ARN"
    fi
  EOT
  ]
}

locals {
  # ARN of the task def currently running in ECS (empty string on first deploy).
  active_task_def_arn = data.external.active_task_definition.result["arn"]
}

# ── IAM — execution role (ECR pull + CloudWatch logs + Secrets) ───────────────

data "aws_iam_policy_document" "task_exec_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:ecs:us-east-2:*:*"]
    }
  }
}

resource "aws_iam_role" "task_exec" {
  name_prefix           = "${var.name}-exec-"
  assume_role_policy    = data.aws_iam_policy_document.task_exec_assume.json
  force_detach_policies = true
  tags                  = var.tags
}

resource "aws_iam_role_policy_attachment" "task_exec_managed" {
  role       = aws_iam_role.task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_policy" "task_exec_secrets" {
  count       = length(var.secret_arns) > 0 ? 1 : 0
  name_prefix = "${var.name}-exec-secrets-"
  description = "Allow ECS execution role to read Secrets Manager secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "GetSecrets"
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.secret_arns
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task_exec_secrets" {
  count      = length(var.secret_arns) > 0 ? 1 : 0
  role       = aws_iam_role.task_exec.name
  policy_arn = aws_iam_policy.task_exec_secrets[0].arn
}

# ── IAM — task role (for app-level AWS API calls via task_iam_statements) ─────

data "aws_iam_policy_document" "task_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task" {
  name_prefix           = "${var.name}-task-"
  assume_role_policy    = data.aws_iam_policy_document.task_assume.json
  force_detach_policies = true
  tags                  = var.tags
}

resource "aws_iam_policy" "task" {
  count       = length(var.task_iam_statements) > 0 ? 1 : 0
  name_prefix = "${var.name}-task-"
  description = "Task role permissions for ${var.name}"

  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [for k, v in var.task_iam_statements : {
      Effect   = try(v.Effect, v.effect, "Allow")
      Action   = try(v.Action, v.actions, [])
      Resource = try(v.Resource, v.resources, ["*"])
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "task" {
  count      = length(var.task_iam_statements) > 0 ? 1 : 0
  role       = aws_iam_role.task.name
  policy_arn = aws_iam_policy.task[0].arn
}

# ── CloudWatch log group ───────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "this" {
  # Use a single-segment path to avoid conflict with the old path
  # (/aws/ecs/{name}/{name}) created by the ECS service module v6 submodule.
  name              = "/aws/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# ── Task definition ───────────────────────────────────────────────────────────
# Using jsonencode() directly guarantees portMappings appears correctly.

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.cpu)
  memory                   = tostring(var.memory)
  execution_role_arn       = aws_iam_role.task_exec.arn
  task_role_arn            = aws_iam_role.task.arn

  # container_definitions is owned by the app CD pipeline (service repo).
  # workload-deploy creates the task definition ONCE on first deploy (bootstrap),
  # then never modifies container_definitions again — no new revisions on each apply.
  # Changes to cpu, memory, IAM roles, or sidecars DO trigger a new revision
  # because those are infrastructure concerns owned by this repo.
  lifecycle {
    ignore_changes = [container_definitions]
  }

  container_definitions = jsonencode(concat([{
    name      = var.name
    image     = var.image
    # cpu is intentionally omitted at container level — Fargate only requires it
    # at task level. Setting container cpu == task cpu causes ECS to reject the
    # task definition when sidecar_containers are present (sum exceeds task cpu).
    memory    = var.memory
    essential = true

    portMappings = [{
      containerPort = var.container_port
      protocol      = "tcp"
    }]

    environment = var.environment_vars

    secrets = var.secrets

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        "awslogs-group"         = aws_cloudwatch_log_group.this.name
        "awslogs-region"        = "us-east-2"
        "awslogs-stream-prefix" = "ecs"
      }
    }

    readonlyRootFilesystem = false
    stopTimeout            = 120
  }], var.sidecar_containers))

  tags = var.tags
}

# ── Target group ───────────────────────────────────────────────────────────────

resource "aws_lb_target_group" "this" {
  name        = var.name
  port        = var.container_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.account.vpc.id

  health_check {
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 10
    matcher             = "200-299"
  }

  deregistration_delay = 30

  tags = var.tags
}

# ── ALB listener rule — host-based routing ────────────────────────────────────

resource "aws_lb_listener_rule" "this" {
  count        = local.listener_arn != null ? 1 : 0
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

module "sg_tasks" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "~> 5.0"

  name        = "${var.name}-tasks"
  description = "ECS tasks for ${var.name} - inbound from ALB only"
  vpc_id      = module.account.vpc.id

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

# ── ECS service (task definition provided externally) ─────────────────────────

module "service" {
  source  = "terraform-aws-modules/ecs/aws//modules/service"
  version = "~> 6.0"

  name        = var.name
  cluster_arn = var.cluster_arn

  cpu    = var.cpu
  memory = var.memory

  desired_count                      = var.desired_count
  deployment_minimum_healthy_percent = 50
  health_check_grace_period_seconds  = var.health_check_grace_period_seconds
  deployment_maximum_percent         = 200

  # Bypass the service module's task definition — we manage it directly above.
  # Use the currently active task def ARN so workload-deploy never reverts the
  # image deployed by app CD pipelines. Falls back to our own task def on first deploy.
  create_task_definition = false
  task_definition_arn = (
    local.active_task_def_arn != ""
    ? local.active_task_def_arn
    : aws_ecs_task_definition.this.arn
  )

  # Skip IAM role creation — we manage them above.
  create_task_exec_iam_role = false
  task_exec_iam_role_arn    = aws_iam_role.task_exec.arn
  create_tasks_iam_role     = false
  tasks_iam_role_arn        = aws_iam_role.task.arn

  # Networking
  subnet_ids            = [for s in module.account.subnets.privates : s.id]
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

  # Auto-scaling
  enable_execute_command   = var.enable_execute_command

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

# ── ECS Exec — SSM permissions for task role ──────────────────────────────────
# Required when enable_execute_command = true.
# Allows SSM Session Manager to open an interactive shell in the container.
resource "aws_iam_role_policy" "ecs_exec_ssm" {
  count = var.enable_execute_command ? 1 : 0
  name  = "${var.name}-ecs-exec-ssm"
  role  = aws_iam_role.task.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ECSExec"
      Effect = "Allow"
      Action = [
        "ssmmessages:CreateControlChannel",
        "ssmmessages:CreateDataChannel",
        "ssmmessages:OpenControlChannel",
        "ssmmessages:OpenDataChannel",
      ]
      Resource = "*"
    }]
  })
}
