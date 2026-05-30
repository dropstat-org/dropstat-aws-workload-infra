module "cluster" {
  source  = "terraform-aws-modules/ecs/aws"
  version = "~> 6.0"

  cluster_name = var.name

  cluster_setting = [{
    name  = "containerInsights"
    value = var.container_insights_enabled ? "enabled" : "disabled"
  }]

  tags = var.tags
}
