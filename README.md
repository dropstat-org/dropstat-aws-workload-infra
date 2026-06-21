> 🌐 [Español](README.es.md)

# dropstat-aws-workload-infra

Reusable **Terraform module library** for the Dropstat workload layer.

This repository contains **only modules** (under `_modules/`) — there is no `live/` directory and no Terragrunt configuration here. The actual deployments (environment wiring, variable values, state) live in the companion repository **`dropstat-aws-workload-deploy`**, which references these modules by Git tag/ref.

**Visibility:** Public. Terraform modules contain no secrets, so the repo is safe to expose. Modules are consumed without a PAT or any authentication via `?ref=master`.

- **Terraform:** `>= 1.11` (required by `terraform-aws-modules/secrets-manager ~> 2.0`)
- **AWS provider:** `v6`
- **Region:** `us-east-2` (hardcoded in a few places — ECS log driver, ECS Exec source-ARN condition, scale-to-zero data lookup)

---

## 1. Overview

`dropstat-aws-workload-infra` is the building-block layer for Dropstat's application workloads on AWS: ECS Fargate services, the data plane (Aurora, ElastiCache, Amazon MQ, SQS), the edge (internal ALB, API Gateway HTTP v2 + WAF, CloudFront), DNS, certificates, secrets, and supporting storage.

Design principles:

1. **`terraform-aws-modules` first.** Every module wraps an official `terraform-aws-modules` registry module wherever one exists. Raw `resource "aws_*"` blocks are used only when no official module covers the case (Amazon MQ, WAFv2, Route53 zones/records, SSM parameters, Transfer Family).
2. **Dynamic VPC/subnet discovery.** Modules that need networking embed a `module "account"` that calls **`tm-aws-account-data`**, which resolves VPC id, subnets (public/private/data/secure), and CIDRs from AWS tags at plan/apply time. Callers never pass `vpc_id` or `subnet_ids`.
3. **Pipeline owns the image.** The `ecs-service` module deliberately yields ownership of the live container image to the application CD pipelines (see the deep dive in §5).

### How it is used

```hcl
# In any terragrunt.hcl / module block inside dropstat-aws-workload-deploy:
terraform {
  source = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/ecs-service?ref=master"
}
```

`master` is the main branch. Pin to a tag or commit SHA for reproducible deploys.

---

## 2. Module catalog

| Module | Purpose | Backing `terraform-aws-modules` | Key features |
|--------|---------|---------------------------------|--------------|
| [`ecs-service`](#ecs-service) | One ECS Fargate service: task def, target group, ALB rule, autoscaling | `ecs//modules/service ~> 6.0` + `security-group ~> 5.0` | Scale-to-zero, sidecars, image ownership handoff, ECS Exec, dual IAM roles |
| [`ecs-cluster`](#ecs-cluster) | ECS cluster | `ecs ~> 6.0` | Container Insights toggle |
| [`alb`](#alb) | Internal ALB (API GW connects via VPC Link) | `alb ~> 9.0` | HTTP→HTTPS redirect, conditional HTTPS listener |
| [`apigw`](#apigw) | API Gateway HTTP v2 + VPC Link + WAF | `apigateway-v2 ~> 5.0` + `security-group ~> 5.0` | Host-based routing to ALB, native WAFv2 ACL |
| [`aurora`](#aurora) | Aurora Serverless v2 (MySQL 8.0) | `rds-aurora ~> 9.0` | Snapshot restore, optional VPN ingress, managed master password |
| [`elasticache`](#elasticache) | Redis cache | `elasticache ~> 1.0` | Single-node Redis 7.1, VPC-CIDR ingress |
| [`mq`](#mq) | Amazon MQ (ActiveMQ) | native `aws_mq_broker` + `security-group ~> 5.0` | Single-instance broker, MQTT/AMQPS/console SGs |
| [`sqs`](#sqs) | SQS queues (bulk) | `sqs ~> 4.0` | `for_each` over queue names, SSE enabled |
| [`workload-secrets`](#workload-secrets) | Per-env secret bundle in Secrets Manager | `secrets-manager ~> 2.0` | Auto-generated + manual secrets, ignore-changes |
| [`dns-records`](#dns-records) | Route53 records in an existing zone | native `aws_route53_record` | No data lookup; safe with dependency-supplied zone id |
| `acm` | ACM certificate with automatic DNS validation | native `aws_acm_certificate*` | Waits for ISSUED before exporting ARN |
| `route53-zone` | Private hosted zone for internal discovery | native `aws_route53_zone` | VPC-associated, `force_destroy` |
| `route53-public-zone` | Public hosted zone | native | (see source) |
| `parameter-store` | Bulk SSM SecureString parameters | native `aws_ssm_parameter` | `ignore_changes = [value]`; values set by pipeline |
| `s3-bucket` | General private bucket | `s3-bucket ~> 4.0` | Encryption, versioning, public-access block |
| `frontend-s3-cloudfront` | Static SPA hosting | `cloudfront ~> 6.0` + `s3-bucket ~> 5.0` | Private S3 + CloudFront OAC, SPA routing function |
| `transfer-family` | SFTP server with Lambda IdP | native `aws_transfer_server` + Lambda | Public SFTP, Secrets-Manager-backed auth |

> The first ten modules are the core workload library and are documented in full below. The remaining modules are supporting infrastructure and summarized in the catalog.

---

## 3. External module reference

| Module | Version | Registry |
|--------|---------|----------|
| terraform-aws-modules/alb | `~> 9.0` | https://registry.terraform.io/modules/terraform-aws-modules/alb/aws |
| terraform-aws-modules/apigateway-v2 | `~> 5.0` | https://registry.terraform.io/modules/terraform-aws-modules/apigateway-v2/aws |
| terraform-aws-modules/rds-aurora | `~> 9.0` | https://registry.terraform.io/modules/terraform-aws-modules/rds-aurora/aws |
| terraform-aws-modules/ecs | `~> 6.0` | https://registry.terraform.io/modules/terraform-aws-modules/ecs/aws |
| terraform-aws-modules/elasticache | `~> 1.0` | https://registry.terraform.io/modules/terraform-aws-modules/elasticache/aws |
| terraform-aws-modules/security-group | `~> 5.0` | https://registry.terraform.io/modules/terraform-aws-modules/security-group/aws |
| terraform-aws-modules/sqs | `~> 4.0` | https://registry.terraform.io/modules/terraform-aws-modules/sqs/aws |
| terraform-aws-modules/secrets-manager | `~> 2.0` | https://registry.terraform.io/modules/terraform-aws-modules/secrets-manager/aws |
| terraform-aws-modules/s3-bucket | `~> 4.0`–`~> 5.0` | https://registry.terraform.io/modules/terraform-aws-modules/s3-bucket/aws |
| terraform-aws-modules/cloudfront | `~> 6.0` | https://registry.terraform.io/modules/terraform-aws-modules/cloudfront/aws |
| terraform-aws-modules/route53 | `~> 4.0` | https://registry.terraform.io/modules/terraform-aws-modules/route53/aws |
| tm-aws-account-data | `master` | https://github.com/dropstat-org/tm-aws-account-data |

---

## 4. VPC / subnet discovery via `tm-aws-account-data`

Every module that needs networking embeds:

```hcl
module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}
```

This eliminates the need to thread `vpc_id` / `subnet_ids` through every module. `tm-aws-account-data` discovers the network by AWS tags at plan/apply time and exposes a structured object:

| Attribute | Meaning | Used by |
|-----------|---------|---------|
| `module.account.vpc.id` | VPC id | all networked modules |
| `module.account.vpc.cidr_block` | VPC CIDR | `elasticache` ingress rule |
| `module.account.subnets.privates[*].id` | private subnet ids | `alb`, `apigw` VPC Link, `ecs-service`, `mq` |
| `module.account.subnets.privates[*].cidr_block` | private subnet CIDRs | `aurora` ingress rule |
| `module.account.subnets.data[*].id` | data-tier subnet ids | `aurora` subnet group |
| `module.account.subnets.secures[*].cidr_block` | TGW-attachment subnet CIDRs (network account) | `aurora` optional VPN access |

Modules with embedded discovery: `alb`, `apigw`, `aurora`, `elasticache`, `mq`, `ecs-service`.

**Cross-account variant.** The `aurora` module can instantiate a *second* `module "account"` against an aliased provider (`aws.network`) to read the network account's TGW-attachment subnets, so it can grant Aurora ingress to the Headscale/Tailscale subnet router without hardcoding CIDRs:

```hcl
module "network_account" {
  count    = var.enable_vpn_access ? 1 : 0
  source   = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
  providers = { aws = aws.network }
}
```

---

## 5. `ecs-service` — deep dive

The most complex module in the library. It provisions a full ECS Fargate service plus everything required to route traffic to it and scale it.

### Resources created

- `aws_ecs_task_definition.this` — managed **directly** (not via the service module's `container_definitions`), because service module v6.12 does not correctly forward `port_mappings` to the container-definition submodule. Using `jsonencode()` guarantees `portMappings` is always emitted.
- `aws_iam_role.task_exec` (+ managed policy + optional Secrets/SSM policies) — **execution role**.
- `aws_iam_role.task` (+ optional inline policy from `task_iam_statements`, + optional ECS-Exec SSM policy) — **task role**.
- `aws_cloudwatch_log_group.this` — `/aws/ecs/{name}` (single-segment path to avoid colliding with the v6 submodule's `/aws/ecs/{name}/{name}`).
- `aws_lb_target_group.this` — IP target type, `/health` HTTP health check.
- `aws_lb_listener_rule.this` — host-header routing (conditional on a listener ARN being present).
- `module.sg_tasks` — security group allowing inbound only from the ALB SG.
- `module.service` — the `terraform-aws-modules/ecs//modules/service` wrapper.
- Scale-to-zero set (optional): 2 `aws_appautoscaling_policy` (StepScaling) + 2 `aws_cloudwatch_metric_alarm`.

### Two IAM roles — execution vs task

| Role | Assumed by | Purpose | Attached permissions |
|------|------------|---------|----------------------|
| **execution role** (`task_exec`) | `ecs-tasks.amazonaws.com` (with `aws:SourceArn` ArnLike condition on `arn:aws:ecs:us-east-2:*:*`) | What ECS the **agent** needs to start the task | `AmazonECSTaskExecutionRolePolicy` (ECR pull + CloudWatch logs), plus `secretsmanager:GetSecretValue` on `secret_arns`, plus `ssm:GetParameter(s)` on `ssm_param_arns` — only created when those lists are non-empty |
| **task role** (`task`) | `ecs-tasks.amazonaws.com` | What the **application** uses for AWS API calls at runtime | inline policy built from `task_iam_statements`, plus `ssmmessages:*` for ECS Exec when `enable_execute_command = true` |

The `task_iam_statements` variable is typed `any` and the policy builder accepts both PascalCase and lowercase keys: `Effect`/`effect`, `Action`/`actions`, `Resource`/`resources`.

### Image ownership handoff (notable quirk)

`workload-deploy` owns infra (env vars, IAM, sizing, networking). The application **CD pipelines** own the live image tag. To stop `workload-deploy` from reverting an image deployed by a pipeline:

1. `data.external.active_task_definition` runs the AWS CLI (`aws ecs describe-services ... --query services[0].taskDefinition`) to read the task-def ARN currently live on the service.
2. The service module is given `create_task_definition = false` and `task_definition_arn = <active ARN, or the freshly-created one on first deploy>`.

So Terraform registers new task-definition revisions (when env/secrets/image change) but **never switches** which revision is live — that switch happens only when an app CD pipeline does a `force-new-deployment`. On first deploy (service doesn't exist yet) the active ARN is `""` and it falls back to `aws_ecs_task_definition.this.arn`.

> This means the module shells out to the AWS CLI during plan. The deploy environment must have `aws` and `bash` available and credentials for `us-east-2`.

### Sidecar containers

`sidecar_containers` (type `any`, default `[]`) is `concat()`-ed onto the primary container inside `jsonencode()`. Each element is a complete container-definition object. The primary container deliberately omits container-level `cpu` — Fargate only requires `cpu` at task level, and setting it per-container makes ECS reject the task when sidecars are present (sum exceeds task cpu).

### ALB integration

- A target group (`target_type = "ip"`) is created and wired into the service via the module's `load_balancer` block.
- A listener rule does host-based routing: `local.listener_arn = https_listener_arn ?? http_listener_arn`. The rule is `count`-gated so the module can apply before any ALB/listener exists (initial bootstrap), then attach on a later apply.
- Task SG ingress is restricted to `alb_security_group_id` on `container_port` only.

### Standard autoscaling

Always-on target tracking on `ALBRequestCountPerTarget` (`scaling_target_value` req/target, default 10), between `min_task_count` and `max_task_count`. `resource_label` is `"${alb_arn_suffix}/${target_group.arn_suffix}"`.

### Scale-to-zero mechanism (optional)

Enabled with `enable_scale_to_zero = true` and `min_task_count = 0`.

```
idle N minutes (RequestCount < 1)  → idle-scale-down alarm → StepScaling ExactCapacity 0
request arrives (ALB has 0 targets → 503) → request-scale-up alarm → StepScaling ExactCapacity 1
```

| Component | Detail |
|-----------|--------|
| `idle_scale_down` alarm | `RequestCount` (AWS/ApplicationELB) `< 1`, period 300s, `evaluation_periods = floor(idle_threshold_minutes / 5)` (min 1), `treat_missing_data = notBreaching` (metric disappears when tasks = 0 → stay idle) |
| `scale_down_to_zero` policy | StepScaling, `ExactCapacity 0` when metric ≤ upper bound 0, cooldown 60s |
| `request_scale_up` alarm | `HTTPCode_ELB_5XX_Count` `>= 1`, period 60s, 1 evaluation period |
| `scale_up_from_zero` policy | StepScaling, `ExactCapacity 1` when metric ≥ lower bound 0, cooldown 60s |

> `idle_threshold_minutes` must be a multiple of 5 (CloudWatch period is fixed at 300s). The CD pipeline's "wake" step must call `aws ecs update-service --desired-count 1` and wait before deploying, so deploys never hit a cold service.

### All input variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | string | — | Service / family / TG name |
| `cluster_arn` | string | — | ECS cluster ARN |
| `cluster_name` | string | — | Cluster name (used by CLI lookup + scaling `resource_id`) |
| `cpu` | number | `1024` | Task CPU |
| `memory` | number | `2048` | Task memory |
| `image` | string | — | Container image (first-deploy fallback only; pipeline owns it after) |
| `container_port` | number | `8080` | Container/TG port |
| `health_check_path` | string | `/health` | TG health-check path |
| `desired_count` | number | `1` | Initial task count |
| `min_task_count` | number | `0` | Autoscaling min (set 0 for scale-to-zero) |
| `max_task_count` | number | `3` | Autoscaling max |
| `scaling_target_value` | number | `10` | ALB req/target for scale-out |
| `alb_security_group_id` | string | — | Only SG allowed inbound to tasks |
| `alb_arn_suffix` | string | — | Required for the request-count metric |
| `http_listener_arn` | string | `null` | HTTP listener for the rule |
| `https_listener_arn` | string | `null` | HTTPS listener (preferred over HTTP) |
| `hostnames` | list(string) | — | Host headers for routing |
| `listener_rule_priority` | number | — | Unique per listener |
| `environment_vars` | list(object{name,value}) | `[]` | Plain env vars |
| `secrets` | list(object{name,valueFrom}) | `[]` | Secret env vars |
| `ssm_param_arns` | list(string) | `[]` | SSM ARNs the exec role may read |
| `secret_arns` | list(string) | `[]` | Secrets Manager ARNs the exec role may read |
| `task_iam_statements` | any | `{}` | Task-role policy statements |
| `log_retention_days` | number | `7` | Log group retention |
| `enable_execute_command` | bool | `false` | ECS Exec (SSM shell into container) |
| `health_check_grace_period_seconds` | number | `120` | Grace for slow-start (Java) apps |
| `sidecar_containers` | any | `[]` | Extra container definitions |
| `enable_scale_to_zero` | bool | `false` | Scale to 0 after idle |
| `idle_threshold_minutes` | number | `60` | Idle minutes before scale-down (multiple of 5) |
| `tags` | map(string) | `{}` | Tags |

### Outputs

| Output | Source |
|--------|--------|
| `service_arn` | `module.service.id` (v6 names the service ARN `id`) |
| `service_name` | `module.service.name` |
| `security_group_id` | tasks SG |
| `target_group_arn` | TG ARN |
| `task_role_arn` | task role |

### Example

```hcl
module "api" {
  source = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/ecs-service?ref=master"

  name         = "dropstat-api"
  cluster_arn  = module.cluster.cluster_arn
  cluster_name = module.cluster.cluster_name

  image          = "123456789012.dkr.ecr.us-east-2.amazonaws.com/dropstat-api:bootstrap"
  container_port = 8080
  cpu            = 1024
  memory         = 2048

  hostnames              = ["api-dev.dropstat-np.com"]
  alb_security_group_id  = module.alb.security_group_id
  alb_arn_suffix         = module.alb.arn_suffix
  https_listener_arn     = module.alb.https_listener_arn
  listener_rule_priority = 100

  environment_vars = [{ name = "SPRING_PROFILES_ACTIVE", value = "dev" }]
  secrets          = [{ name = "JWT_SECRET_KEY", valueFrom = "${module.secrets.secret_arn}:jwt_secret_key::" }]
  secret_arns      = [module.secrets.secret_arn]

  # Optional: idle to zero overnight in dev
  min_task_count         = 0
  enable_scale_to_zero   = true
  idle_threshold_minutes = 30

  tags = local.tags
}
```

---

## 6. Core module reference

### `ecs-cluster`

ECS cluster via `terraform-aws-modules/ecs ~> 6.0`.

- **Resources:** ECS cluster.
- **Quirk:** `cluster_setting` is a **list** `[{...}]` in v6 (was an object in v5).
- **Inputs:** `name`, `container_insights_enabled` (bool, default `false`), `tags`.
- **Outputs:** `cluster_arn`, `cluster_name`, `cluster_id`.

```hcl
module "cluster" {
  source                     = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/ecs-cluster?ref=master"
  name                       = "dropstat-dev"
  container_insights_enabled = true
}
```

---

### `alb`

Internal Application Load Balancer via `terraform-aws-modules/alb ~> 9.0`. Not internet-facing — the API Gateway reaches it through a VPC Link.

- **Resources:** ALB, security group, listeners (HTTP always; HTTPS when `certificate_arn` set).
- **Behavior:** SG allows 80/443 from `0.0.0.0/0`. With a cert, port 80 issues an `HTTP_301` redirect to 443 and the HTTPS listener defaults to a `404 fixed_response`; without a cert, port 80 itself returns the `404 fixed_response`. Per-service routing is added later by `ecs-service` listener rules.
- **Quirk:** in v9 the action type (`redirect` / `fixed_response` / `forward`) is a **top-level key** on the listener object — there is no `action {}` wrapper.
- **Inputs:** `name`, `certificate_arn` (default `null`), `tags`.
- **Outputs:** `arn`, `arn_suffix`, `dns_name`, `zone_id`, `security_group_id`, `http_listener_arn`, `https_listener_arn` (last two via `try(...)`).

```hcl
module "alb" {
  source          = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/alb?ref=master"
  name            = "dropstat-dev"
  certificate_arn = module.acm.acm_certificate_arn
}
```

---

### `apigw`

API Gateway HTTP v2 + VPC Link + WAF via `terraform-aws-modules/apigateway-v2 ~> 5.0`. One gateway per environment, routes by hostname to the internal ALB.

- **Resources:** HTTP API, VPC Link, routes/integrations, `$default` stage, VPC-Link SG (`security-group` module), and — when `waf_enabled` — a native `aws_wafv2_web_acl` + association.
- **Routing:** for each entry in `services`, a route `"{method} {route}"` with an `HTTP_PROXY` integration over `VPC_LINK` to `alb_listener_arn`, rewriting `host` to `svc.hostname`.
- **WAF (REGIONAL):** AWS managed CommonRuleSet (OWASP), KnownBadInputs (SQLi/XSS), AmazonIpReputationList, plus a per-IP rate-based rule at `waf_rate_limit`.
- **Quirks:** v5 moved integrations **inside** routes, and key names changed (`type` not `integration_type`, `uri` not `integration_uri`, `method` not `integration_method`). Custom domain is guarded with `create_domain_name = domain_name != null` because the module fails on `null` in `replace()`/`startswith()`. `create_certificate = false` and `create_domain_records = false` — the cert is brought in and the Route53 record is managed by a separate DNS module. No official WAFv2 module exists, so WAF resources are native.

| Variable | Type | Default |
|----------|------|---------|
| `name` | string | — |
| `alb_listener_arn` | string | — |
| `domain_name` | string | `null` |
| `certificate_arn` | string | `null` |
| `services` | map(object{method,route,hostname}) | — |
| `throttling_burst_limit` | number | `500` |
| `throttling_rate_limit` | number | `1000` |
| `waf_enabled` | bool | `true` |
| `waf_rate_limit` | number | `1000` |
| `tags` | map(string) | `{}` |

- **Outputs:** `api_id`, `api_endpoint`, `stage_arn`, `domain_name`, `domain_target`, `waf_arn`.

```hcl
module "apigw" {
  source           = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/apigw?ref=master"
  name             = "dropstat-dev"
  alb_listener_arn = module.alb.https_listener_arn
  domain_name      = "api-dev.dropstat-np.com"
  certificate_arn  = module.acm.acm_certificate_arn
  services = {
    api = { method = "ANY", route = "/{proxy+}", hostname = "api-dev.dropstat-np.com" }
  }
}
```

---

### `aurora`

Aurora Serverless v2 (MySQL 8.0) via `terraform-aws-modules/rds-aurora ~> 9.0`. Replaces the legacy prod `db.m5.4xlarge` for dev/staging/prod.

- **Resources:** Aurora cluster (`db.serverless` writer), DB subnet group (in **data-tier** subnets), security group rules, managed master-user password in Secrets Manager.
- **Behavior:** `manage_master_user_password = true` (password auto-stored in Secrets Manager). CloudWatch log exports: `audit`, `error`, `general`, `slowquery`. Ingress allowed only from private-subnet CIDRs (more restrictive than VPC CIDR); optionally from the network account's TGW-attachment subnets when `enable_vpn_access = true`.
- **Snapshot restore quirk:** when `snapshot_identifier` is set, `database_name` and `master_username` are forced to `null` (inherited from the snapshot — passing them errors). `engine_version` is left `null` so Aurora auto-selects a snapshot-compatible version (pinning `"8.0"` can resolve to a minor newer than the snapshot's source and fail).

| Variable | Type | Default | Notes |
|----------|------|---------|-------|
| `name` | string | — | |
| `database_name` | string | `dropstat` | ignored on snapshot restore |
| `master_username` | string | `appuser` | ignored on snapshot restore |
| `db_subnet_group_name` | string | `null` | when null, module creates one |
| `min_capacity` | number | `0.5` | Serverless v2 ACU min |
| `max_capacity` | number | `2.0` | Serverless v2 ACU max |
| `skip_final_snapshot` | bool | `true` | |
| `deletion_protection` | bool | `false` | |
| `copy_tags_to_snapshot` | bool | `false` | |
| `monitoring_interval` | number | `0` | enhanced monitoring |
| `performance_insights_enabled` | bool | `false` | |
| `backup_retention_period` | number | `7` | window `07:00-08:00` |
| `snapshot_identifier` | string | `null` | restore source |
| `engine_version` | string | `null` | explicit only for non-Aurora MySQL snapshots |
| `enable_vpn_access` | bool | `false` | requires `aws.network` aliased provider |
| `tags` | map(string) | `{}` | |

- **Outputs:** `cluster_endpoint`, `cluster_reader_endpoint`, `cluster_id`, `master_user_secret_arn`, `security_group_id`.

```hcl
module "aurora" {
  source           = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/aurora?ref=master"
  name             = "dropstat-dev"
  min_capacity     = 0.5
  max_capacity     = 4.0
  enable_vpn_access = true
  providers        = { aws.network = aws.network }
}
```

---

### `elasticache`

Single-node Redis 7.1 via `terraform-aws-modules/elasticache ~> 1.0`.

- **Resources:** ElastiCache cluster (no replication group), SG.
- **Behavior:** port 6379, ingress from the **VPC CIDR** (a single `cidr_ipv4`, because `aws_vpc_security_group_ingress_rule` accepts one CIDR — covers all private subnets without per-subnet rules), `apply_immediately`, auto minor upgrades.
- **Inputs:** `name`, `node_type` (`cache.t4g.micro`), `num_cache_nodes` (`1`), `snapshot_retention_limit` (`0`), `tags`.
- **Outputs:** `endpoint` (`try(... cluster_cache_nodes[0].address, null)`), `port` (6379), `security_group_id`.

```hcl
module "redis" {
  source    = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/elasticache?ref=master"
  name      = "dropstat-dev"
  node_type = "cache.t4g.micro"
}
```

---

### `mq`

Amazon MQ (ActiveMQ) single-instance broker — native `aws_mq_broker` (no official module) + `security-group ~> 5.0`.

- **Resources:** MQ broker, SG.
- **Behavior:** `SINGLE_INSTANCE` deployment; when not public, placed in the first private subnet. SG opens MQTT (1883), AMQPS (5671), and the ActiveMQ web console (8162) for each SG in `allowed_security_group_ids`. Sunday 06:00 UTC maintenance window. General logging on, audit off.
- **Inputs:** `name`, `allowed_security_group_ids` (`[]`), `instance_type` (`mq.t3.micro`), `engine_version` (`5.18`), `publicly_accessible` (`false`), `admin_username` (`dropstat`), `admin_password` (sensitive, required), `tags`.
- **Outputs:** `broker_id`, `broker_arn`, `mqtt_endpoint` (`ssl://...`), `console_url`, `security_group_id`.

```hcl
module "mq" {
  source                     = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/mq?ref=master"
  name                       = "dropstat-dev"
  admin_password             = module.secrets.mqtt_password
  allowed_security_group_ids = [module.api.security_group_id]
}
```

---

### `sqs`

Bulk SQS queue creation via `terraform-aws-modules/sqs ~> 4.0`.

- **Resources:** one queue per entry in `queue_names` (`for_each`), SQS-managed SSE on.
- **Inputs:** `queue_names` (list(string)), `message_retention_seconds` (`345600` = 4 days), `visibility_timeout_seconds` (`30`), `tags`.
- **Outputs:** `queue_urls` (name→url map), `queue_arns` (name→arn map).

```hcl
module "queues" {
  source      = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/sqs?ref=master"
  queue_names = ["dropstat-events", "dropstat-notifications"]
}
```

---

### `workload-secrets`

Per-environment secret bundle in a single Secrets Manager secret (`dropstat/{env}/workload`) as a JSON object, via `terraform-aws-modules/secrets-manager ~> 2.0`.

- **Resources:** two `random_password` (auto-generated), one Secrets Manager secret.
- **Auto-generated:** `mqtt_password` (32 chars, `override_special` excludes `, : =` which Amazon MQ rejects) and `jwt_secret_key` (64 chars, no special). Both keyed for rotation.
- **Manual:** `nursa_dropstat_password`, `nursa_dropstat_user`, `nursa_client_id`, `nursa_user_name` — seeded with `REPLACE_ME` and then edited directly in Secrets Manager; the module sets `ignore_secret_changes = true` so Terraform never reverts them. The whole blob is wrapped in `sensitive()`. `recovery_window_in_days = 0`.
- **Inputs:** `env` (required), the four `nursa_*` (default `REPLACE_ME`), `tags`.
- **Outputs:** `secret_arn` (use as `secret_arn:key::`), `secret_name`, `mqtt_username` (`dropstat`), `mqtt_password` (sensitive).

```hcl
module "secrets" {
  source = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/workload-secrets?ref=master"
  env    = "dev"
}
```

---

### `dns-records`

Route53 records in an **existing** zone, using native `aws_route53_record` — no `data` lookup, so it works cleanly when `zone_id` comes from a dependency (avoids "zone not found" during first apply).

- **Inputs:** `zone_id` (required), `zone_name` (docs only), `records` (list of `{name,type,ttl,records}`).
- **Outputs:** `zone_id` (pass-through).

```hcl
module "dns" {
  source  = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/dns-records?ref=master"
  zone_id = module.zone.zone_id
  records = [
    { name = "api-dev.dropstat-np.com", type = "CNAME", ttl = 300, records = [module.apigw.domain_target] }
  ]
}
```

---

## 7. Consuming these modules from `dropstat-aws-workload-deploy`

The deploy repo wires modules together per environment. Outputs feed the next module's inputs, forming the dependency graph:

```
ecs-cluster ─┐
acm ─► alb ──┼─► ecs-service ◄─ workload-secrets
             └─► apigw ──► dns-records
aurora / elasticache / mq / sqs  (data plane, referenced by ecs-service env/secrets)
```

```hcl
# Pin a tag/SHA for reproducible deploys:
terraform {
  source = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/ecs-service?ref=v1.4.0"
}
```

Typical wiring (conceptually):

1. `acm` → certificate ARN → `alb` and `apigw`.
2. `ecs-cluster` → `cluster_arn` / `cluster_name` → `ecs-service`.
3. `alb` → `security_group_id`, `arn_suffix`, listener ARNs → `ecs-service`.
4. `workload-secrets` → `secret_arn` + `secret_arns` → `ecs-service` (`secrets` / exec-role permissions) and `mqtt_password` → `mq`.
5. `apigw` → `domain_target` → `dns-records`.

> Because `ecs-service` shells out via `data.external`, the deploy runner needs `aws` + `bash` on PATH and credentials for `us-east-2`.

---

## 8. AWS provider v6 compatibility notes

The library was migrated to AWS provider v6 / ECS module v6 (from v5.12). Notable adjustments:

- **ECS service module v6:** removed `inference_accelerator` (incompatible with v6); `cloudwatch_log_group_retention_in_days` moved inside `container_definitions`; `tasks_iam_role_statements` became a `list(object)`; the service ARN output is now `id`, not `arn`.
- **ECS cluster v6:** `cluster_setting` is a list `[{}]`, not an object.
- **ALB v9:** action type is a top-level listener key (`redirect`/`fixed_response`/`forward`); no `action` wrapper.
- **apigateway-v2 v5:** integrations moved inside routes; key renames `type`/`uri`/`method`.
- **WAFv2:** `override_action { none {} }` and `action { block {} }` written multi-line.
- **variables.tf:** multi-line form throughout (single-line `;` separators are invalid under v6 tooling).

---

## 9. Security group patterns

| Module | Pattern | Notes |
|--------|---------|-------|
| `ecs-service` | `ingress_with_source_security_group_id` from the ALB SG on `container_port`; egress `all-all` | Tasks accept traffic only from the ALB |
| `alb` | `security_group_ingress_rules` 80/443 from `0.0.0.0/0`; egress `-1` to `0.0.0.0/0` | Built into ALB module v9 |
| `apigw` (VPC Link) | `egress_with_cidr_blocks` 80/443 to `0.0.0.0/0` | VPC Link reaches the internal ALB |
| `aurora` | `security_group_rules` with `cidr_blocks` = private-subnet CIDRs (+ optional TGW-attachment CIDRs) | Module uses legacy `aws_security_group_rule`, so `source_security_group_id` semantics apply |
| `elasticache` | `security_group_rules` with a single `cidr_ipv4` = VPC CIDR | Module uses `aws_vpc_security_group_ingress_rule` (one CIDR per rule) |
| `mq` | `ingress_with_source_security_group_id` for 1883/5671/8162 per allowed SG; egress `all-all` | `flatten()` over `allowed_security_group_ids` |

All SGs use `terraform-aws-modules/security-group ~> 5.0` except where the backing module manages its own SG (ALB, Aurora, ElastiCache).
