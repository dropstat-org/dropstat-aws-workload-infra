locals {
  account_name = "dev"
  account_id   = "453531893227"
  role_arn     = "arn:aws:iam::453531893227:role/TerraformCI"
  region       = "us-east-2"

  log_retention_days         = 7
  container_insights_enabled = false  # enable in prod
  certificate_arn            = null   # set to ACM ARN when HTTPS is ready

  apigw = {
    domain_name            = null     # set to e.g. "api-dev.dropstat.com" when DNS is ready
    throttling_burst_limit = 200
    throttling_rate_limit  = 500
    waf_enabled            = false    # enable in prod — costs ~$5/mo base + per rule
    waf_rate_limit         = 1000     # req per 5min per IP before blocking
  }

  aurora = {
    min_capacity                 = 0.5
    max_capacity                 = 2.0
    skip_final_snapshot          = true
    deletion_protection          = false
    monitoring_interval          = 0
    performance_insights_enabled = false
  }

  elasticache = {
    node_type       = "cache.t4g.micro"
    num_cache_nodes = 1
  }

  mq = {
    instance_type       = "mq.t3.micro"
    publicly_accessible = false
  }

  queue_suffix = "-dev"
}
