> 🌐 [English](README.md)

# dropstat-aws-workload-infra

**Librería de módulos Terraform** reutilizables para la capa de workload de Dropstat.

Este repositorio contiene **solo módulos** (en `_modules/`) — no hay directorio `live/` ni configuración Terragrunt. Los despliegues reales (cableado de ambientes, valores de variables, estado) viven en el repositorio compañero **`dropstat-aws-workload-deploy`**, que referencia estos módulos por tag/ref de Git.

**Visibilidad:** Público. Los módulos Terraform no contienen secretos, así que el repo es seguro de exponer. Los módulos se consumen sin PAT ni autenticación vía `?ref=master`.

- **Terraform:** `>= 1.11` (requerido por `terraform-aws-modules/secrets-manager ~> 2.0`)
- **AWS provider:** `v6`
- **Región:** `us-east-2` (hardcodeada en algunos puntos — log driver de ECS, condición source-ARN de ECS Exec, lookup del data source de scale-to-zero)

---

## 1. Visión general

`dropstat-aws-workload-infra` es la capa de bloques de construcción para los workloads de aplicación de Dropstat en AWS: servicios ECS Fargate, el plano de datos (Aurora, ElastiCache, Amazon MQ, SQS), el borde (ALB interno, API Gateway HTTP v2 + WAF, CloudFront), DNS, certificados, secretos y almacenamiento de soporte.

Principios de diseño:

1. **`terraform-aws-modules` primero.** Cada módulo envuelve un módulo oficial del registry `terraform-aws-modules` donde exista. Los bloques `resource "aws_*"` sueltos se usan solo cuando ningún módulo oficial cubre el caso (Amazon MQ, WAFv2, zonas/records de Route53, parámetros SSM, Transfer Family).
2. **Descubrimiento dinámico de VPC/subnets.** Los módulos que necesitan red embeben un `module "account"` que llama a **`tm-aws-account-data`**, que resuelve el id de VPC, las subnets (public/private/data/secure) y los CIDRs por tags de AWS al momento del plan/apply. Los callers nunca pasan `vpc_id` ni `subnet_ids`.
3. **El pipeline es dueño de la imagen.** El módulo `ecs-service` cede deliberadamente la propiedad de la imagen viva a los pipelines de CD de las aplicaciones (ver el deep dive en §5).

### Cómo se usa

```hcl
# En cualquier terragrunt.hcl / bloque module dentro de dropstat-aws-workload-deploy:
terraform {
  source = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/ecs-service?ref=master"
}
```

`master` es la rama principal. Fija un tag o SHA de commit para despliegues reproducibles.

---

## 2. Catálogo de módulos

| Módulo | Propósito | `terraform-aws-modules` de respaldo | Características clave |
|--------|-----------|-------------------------------------|----------------------|
| [`ecs-service`](#ecs-service) | Un servicio ECS Fargate: task def, target group, regla de ALB, autoscaling | `ecs//modules/service ~> 6.0` + `security-group ~> 5.0` | Scale-to-zero, sidecars, traspaso de propiedad de imagen, ECS Exec, dos roles IAM |
| [`ecs-cluster`](#ecs-cluster) | Cluster ECS | `ecs ~> 6.0` | Toggle de Container Insights |
| [`alb`](#alb) | ALB interno (API GW conecta vía VPC Link) | `alb ~> 9.0` | Redirect HTTP→HTTPS, listener HTTPS condicional |
| [`apigw`](#apigw) | API Gateway HTTP v2 + VPC Link + WAF | `apigateway-v2 ~> 5.0` + `security-group ~> 5.0` | Routing por hostname hacia ALB, ACL WAFv2 nativa |
| [`aurora`](#aurora) | Aurora Serverless v2 (MySQL 8.0) | `rds-aurora ~> 9.0` | Restore de snapshot, ingress VPN opcional, master password gestionado |
| [`elasticache`](#elasticache) | Cache Redis | `elasticache ~> 1.0` | Redis 7.1 single-node, ingress por CIDR de VPC |
| [`mq`](#mq) | Amazon MQ (ActiveMQ) | `aws_mq_broker` nativo + `security-group ~> 5.0` | Broker single-instance, SGs MQTT/AMQPS/consola |
| [`sqs`](#sqs) | Colas SQS (en bloque) | `sqs ~> 4.0` | `for_each` sobre nombres de cola, SSE activado |
| [`workload-secrets`](#workload-secrets) | Bundle de secretos por ambiente en Secrets Manager | `secrets-manager ~> 2.0` | Secretos auto-generados + manuales, ignore-changes |
| [`dns-records`](#dns-records) | Records Route53 en una zona existente | `aws_route53_record` nativo | Sin data lookup; seguro con zone id de dependencia |
| `acm` | Certificado ACM con validación DNS automática | `aws_acm_certificate*` nativo | Espera ISSUED antes de exportar el ARN |
| `route53-zone` | Zona hosteada privada para discovery interno | `aws_route53_zone` nativo | Asociada a VPC, `force_destroy` |
| `route53-public-zone` | Zona hosteada pública | nativo | (ver fuente) |
| `parameter-store` | Parámetros SSM SecureString en bloque | `aws_ssm_parameter` nativo | `ignore_changes = [value]`; valores los pone el pipeline |
| `s3-bucket` | Bucket privado de propósito general | `s3-bucket ~> 4.0` | Cifrado, versionado, bloqueo de acceso público |
| `frontend-s3-cloudfront` | Hosting de SPA estática | `cloudfront ~> 6.0` + `s3-bucket ~> 5.0` | S3 privado + CloudFront OAC, función de routing SPA |
| `transfer-family` | Servidor SFTP con IdP Lambda | `aws_transfer_server` nativo + Lambda | SFTP público, auth respaldada por Secrets Manager |

> Los primeros diez módulos son la librería de workload central y se documentan completos abajo. Los demás son infraestructura de soporte y se resumen en el catálogo.

---

## 3. Referencia de módulos externos

| Módulo | Versión | Registry |
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

## 4. Descubrimiento de VPC / subnets vía `tm-aws-account-data`

Cada módulo que necesita red embebe:

```hcl
module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}
```

Esto elimina la necesidad de propagar `vpc_id` / `subnet_ids` por cada módulo. `tm-aws-account-data` descubre la red por tags de AWS al momento del plan/apply y expone un objeto estructurado:

| Atributo | Significado | Usado por |
|----------|-------------|-----------|
| `module.account.vpc.id` | id de la VPC | todos los módulos con red |
| `module.account.vpc.cidr_block` | CIDR de la VPC | regla de ingress de `elasticache` |
| `module.account.subnets.privates[*].id` | ids de subnets privadas | `alb`, VPC Link de `apigw`, `ecs-service`, `mq` |
| `module.account.subnets.privates[*].cidr_block` | CIDRs de subnets privadas | regla de ingress de `aurora` |
| `module.account.subnets.data[*].id` | ids de subnets data-tier | subnet group de `aurora` |
| `module.account.subnets.secures[*].cidr_block` | CIDRs de subnets TGW-attachment (cuenta network) | acceso VPN opcional de `aurora` |

Módulos con descubrimiento embebido: `alb`, `apigw`, `aurora`, `elasticache`, `mq`, `ecs-service`.

**Variante cross-account.** El módulo `aurora` puede instanciar un *segundo* `module "account"` contra un provider con alias (`aws.network`) para leer las subnets TGW-attachment de la cuenta network, de modo que pueda dar ingress a Aurora desde el subnet router de Headscale/Tailscale sin hardcodear CIDRs:

```hcl
module "network_account" {
  count    = var.enable_vpn_access ? 1 : 0
  source   = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
  providers = { aws = aws.network }
}
```

---

## 5. `ecs-service` — deep dive

El módulo más complejo de la librería. Provisiona un servicio ECS Fargate completo más todo lo necesario para enrutar tráfico hacia él y escalarlo.

### Recursos creados

- `aws_ecs_task_definition.this` — gestionado **directamente** (no vía el `container_definitions` del módulo de servicio), porque el módulo de servicio v6.12 no propaga correctamente los `port_mappings` al submódulo de container-definition. Usar `jsonencode()` garantiza que `portMappings` siempre se emita.
- `aws_iam_role.task_exec` (+ policy gestionada + policies opcionales de Secrets/SSM) — **rol de ejecución**.
- `aws_iam_role.task` (+ policy inline opcional desde `task_iam_statements`, + policy SSM opcional de ECS-Exec) — **rol de task**.
- `aws_cloudwatch_log_group.this` — `/aws/ecs/{name}` (ruta de un solo segmento para evitar colisión con `/aws/ecs/{name}/{name}` del submódulo v6).
- `aws_lb_target_group.this` — target type IP, health check HTTP `/health`.
- `aws_lb_listener_rule.this` — routing por host-header (condicional a que exista un ARN de listener).
- `module.sg_tasks` — security group que permite inbound solo desde el SG del ALB.
- `module.service` — el wrapper de `terraform-aws-modules/ecs//modules/service`.
- Conjunto scale-to-zero (opcional): 2 `aws_appautoscaling_policy` (StepScaling) + 2 `aws_cloudwatch_metric_alarm`.

### Dos roles IAM — ejecución vs task

| Rol | Asumido por | Propósito | Permisos adjuntos |
|-----|-------------|-----------|-------------------|
| **rol de ejecución** (`task_exec`) | `ecs-tasks.amazonaws.com` (con condición ArnLike de `aws:SourceArn` sobre `arn:aws:ecs:us-east-2:*:*`) | Lo que el **agente** de ECS necesita para arrancar la task | `AmazonECSTaskExecutionRolePolicy` (pull de ECR + logs de CloudWatch), más `secretsmanager:GetSecretValue` sobre `secret_arns`, más `ssm:GetParameter(s)` sobre `ssm_param_arns` — creados solo cuando esas listas no están vacías |
| **rol de task** (`task`) | `ecs-tasks.amazonaws.com` | Lo que la **aplicación** usa para llamadas a la API de AWS en runtime | policy inline construida desde `task_iam_statements`, más `ssmmessages:*` para ECS Exec cuando `enable_execute_command = true` |

La variable `task_iam_statements` es de tipo `any` y el constructor de policy acepta claves en PascalCase y minúscula: `Effect`/`effect`, `Action`/`actions`, `Resource`/`resources`.

### Traspaso de propiedad de la imagen (quirk notable)

`workload-deploy` es dueño de la infra (env vars, IAM, sizing, red). Los **pipelines de CD** de las aplicaciones son dueños del tag de imagen vivo. Para impedir que `workload-deploy` revierta una imagen desplegada por un pipeline:

1. `data.external.active_task_definition` ejecuta el AWS CLI (`aws ecs describe-services ... --query services[0].taskDefinition`) para leer el ARN de la task-def actualmente viva en el servicio.
2. Al módulo de servicio se le pasa `create_task_definition = false` y `task_definition_arn = <ARN activo, o el recién creado en el primer deploy>`.

Así Terraform registra nuevas revisiones de task-definition (cuando cambian env/secrets/imagen) pero **nunca cambia** cuál revisión está viva — ese cambio solo ocurre cuando un pipeline de CD de app hace un `force-new-deployment`. En el primer deploy (el servicio aún no existe) el ARN activo es `""` y cae al fallback `aws_ecs_task_definition.this.arn`.

> Esto significa que el módulo invoca el AWS CLI durante el plan. El entorno de deploy debe tener `aws` y `bash` disponibles y credenciales para `us-east-2`.

### Contenedores sidecar

`sidecar_containers` (tipo `any`, default `[]`) se hace `concat()` sobre el contenedor primario dentro de `jsonencode()`. Cada elemento es un objeto completo de container-definition. El contenedor primario omite deliberadamente el `cpu` a nivel de contenedor — Fargate solo requiere `cpu` a nivel de task, y fijarlo por contenedor hace que ECS rechace la task cuando hay sidecars (la suma excede el cpu de la task).

### Integración con ALB

- Se crea un target group (`target_type = "ip"`) y se cablea al servicio vía el bloque `load_balancer` del módulo.
- Una regla de listener hace routing por host: `local.listener_arn = https_listener_arn ?? http_listener_arn`. La regla está gateada con `count` para que el módulo pueda aplicar antes de que exista cualquier ALB/listener (bootstrap inicial) y se adjunte en un apply posterior.
- El ingress del SG de tasks se restringe a `alb_security_group_id` solo en `container_port`.

### Autoscaling estándar

Target tracking siempre activo sobre `ALBRequestCountPerTarget` (`scaling_target_value` req/target, default 10), entre `min_task_count` y `max_task_count`. El `resource_label` es `"${alb_arn_suffix}/${target_group.arn_suffix}"`.

### Mecanismo scale-to-zero (opcional)

Se activa con `enable_scale_to_zero = true` y `min_task_count = 0`.

```
inactivo N minutos (RequestCount < 1)  → alarma idle-scale-down → StepScaling ExactCapacity 0
llega una request (ALB con 0 targets → 503) → alarma request-scale-up → StepScaling ExactCapacity 1
```

| Componente | Detalle |
|------------|---------|
| alarma `idle_scale_down` | `RequestCount` (AWS/ApplicationELB) `< 1`, periodo 300s, `evaluation_periods = floor(idle_threshold_minutes / 5)` (mín 1), `treat_missing_data = notBreaching` (la métrica desaparece cuando tasks = 0 → permanecer inactivo) |
| policy `scale_down_to_zero` | StepScaling, `ExactCapacity 0` cuando la métrica ≤ upper bound 0, cooldown 60s |
| alarma `request_scale_up` | `HTTPCode_ELB_5XX_Count` `>= 1`, periodo 60s, 1 periodo de evaluación |
| policy `scale_up_from_zero` | StepScaling, `ExactCapacity 1` cuando la métrica ≥ lower bound 0, cooldown 60s |

> `idle_threshold_minutes` debe ser múltiplo de 5 (el periodo de CloudWatch es fijo en 300s). El paso de "wake" del pipeline de CD debe llamar `aws ecs update-service --desired-count 1` y esperar antes de desplegar, para que los deploys nunca peguen contra un servicio frío.

### Todas las variables de entrada

| Variable | Tipo | Default | Descripción |
|----------|------|---------|-------------|
| `name` | string | — | Nombre del servicio / family / TG |
| `cluster_arn` | string | — | ARN del cluster ECS |
| `cluster_name` | string | — | Nombre del cluster (usado por el lookup del CLI + `resource_id` de scaling) |
| `cpu` | number | `1024` | CPU de la task |
| `memory` | number | `2048` | Memoria de la task |
| `image` | string | — | Imagen del contenedor (solo fallback en el primer deploy; luego el pipeline es dueño) |
| `container_port` | number | `8080` | Puerto del contenedor/TG |
| `health_check_path` | string | `/health` | Ruta de health check del TG |
| `desired_count` | number | `1` | Conteo inicial de tasks |
| `min_task_count` | number | `0` | Mín de autoscaling (poner 0 para scale-to-zero) |
| `max_task_count` | number | `3` | Máx de autoscaling |
| `scaling_target_value` | number | `10` | Req/target del ALB para scale-out |
| `alb_security_group_id` | string | — | Único SG permitido inbound a las tasks |
| `alb_arn_suffix` | string | — | Requerido para la métrica de request-count |
| `http_listener_arn` | string | `null` | Listener HTTP para la regla |
| `https_listener_arn` | string | `null` | Listener HTTPS (preferido sobre HTTP) |
| `hostnames` | list(string) | — | Host headers para routing |
| `listener_rule_priority` | number | — | Único por listener |
| `environment_vars` | list(object{name,value}) | `[]` | Env vars planas |
| `secrets` | list(object{name,valueFrom}) | `[]` | Env vars de secretos |
| `ssm_param_arns` | list(string) | `[]` | ARNs SSM que el rol exec puede leer |
| `secret_arns` | list(string) | `[]` | ARNs de Secrets Manager que el rol exec puede leer |
| `task_iam_statements` | any | `{}` | Statements de policy del rol de task |
| `log_retention_days` | number | `7` | Retención del log group |
| `enable_execute_command` | bool | `false` | ECS Exec (shell SSM hacia el contenedor) |
| `health_check_grace_period_seconds` | number | `120` | Gracia para apps de arranque lento (Java) |
| `sidecar_containers` | any | `[]` | Definiciones de contenedor extra |
| `enable_scale_to_zero` | bool | `false` | Escalar a 0 tras inactividad |
| `idle_threshold_minutes` | number | `60` | Minutos inactivo antes de scale-down (múltiplo de 5) |
| `tags` | map(string) | `{}` | Tags |

### Outputs

| Output | Fuente |
|--------|--------|
| `service_arn` | `module.service.id` (v6 nombra el ARN del servicio como `id`) |
| `service_name` | `module.service.name` |
| `security_group_id` | SG de tasks |
| `target_group_arn` | ARN del TG |
| `task_role_arn` | rol de task |

### Ejemplo

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

  # Opcional: bajar a cero de noche en dev
  min_task_count         = 0
  enable_scale_to_zero   = true
  idle_threshold_minutes = 30

  tags = local.tags
}
```

---

## 6. Referencia de módulos centrales

### `ecs-cluster`

Cluster ECS vía `terraform-aws-modules/ecs ~> 6.0`.

- **Recursos:** cluster ECS.
- **Quirk:** `cluster_setting` es una **lista** `[{...}]` en v6 (era un objeto en v5).
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

Application Load Balancer interno vía `terraform-aws-modules/alb ~> 9.0`. No internet-facing — el API Gateway lo alcanza por un VPC Link.

- **Recursos:** ALB, security group, listeners (HTTP siempre; HTTPS cuando se pasa `certificate_arn`).
- **Comportamiento:** el SG permite 80/443 desde `0.0.0.0/0`. Con cert, el puerto 80 emite un redirect `HTTP_301` a 443 y el listener HTTPS hace default a un `fixed_response` 404; sin cert, el propio puerto 80 devuelve el `fixed_response` 404. El routing por servicio lo agregan después las reglas de listener de `ecs-service`.
- **Quirk:** en v9 el tipo de acción (`redirect` / `fixed_response` / `forward`) es una **clave top-level** del objeto listener — no hay wrapper `action {}`.
- **Inputs:** `name`, `certificate_arn` (default `null`), `tags`.
- **Outputs:** `arn`, `arn_suffix`, `dns_name`, `zone_id`, `security_group_id`, `http_listener_arn`, `https_listener_arn` (los dos últimos vía `try(...)`).

```hcl
module "alb" {
  source          = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/alb?ref=master"
  name            = "dropstat-dev"
  certificate_arn = module.acm.acm_certificate_arn
}
```

---

### `apigw`

API Gateway HTTP v2 + VPC Link + WAF vía `terraform-aws-modules/apigateway-v2 ~> 5.0`. Un gateway por ambiente, enruta por hostname hacia el ALB interno.

- **Recursos:** HTTP API, VPC Link, routes/integrations, stage `$default`, SG del VPC Link (módulo `security-group`), y — cuando `waf_enabled` — un `aws_wafv2_web_acl` nativo + asociación.
- **Routing:** por cada entrada en `services`, una route `"{method} {route}"` con integración `HTTP_PROXY` sobre `VPC_LINK` hacia `alb_listener_arn`, reescribiendo `host` a `svc.hostname`.
- **WAF (REGIONAL):** CommonRuleSet gestionado por AWS (OWASP), KnownBadInputs (SQLi/XSS), AmazonIpReputationList, más una regla rate-based por IP en `waf_rate_limit`.
- **Quirks:** v5 movió los integrations **dentro** de las routes, y cambiaron los nombres de clave (`type` no `integration_type`, `uri` no `integration_uri`, `method` no `integration_method`). El dominio custom se gatea con `create_domain_name = domain_name != null` porque el módulo falla con `null` en `replace()`/`startswith()`. `create_certificate = false` y `create_domain_records = false` — el cert se trae externamente y el record de Route53 lo gestiona un módulo DNS aparte. No existe módulo oficial de WAFv2, por eso los recursos WAF son nativos.

| Variable | Tipo | Default |
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

Aurora Serverless v2 (MySQL 8.0) vía `terraform-aws-modules/rds-aurora ~> 9.0`. Reemplaza el legacy `db.m5.4xlarge` de prod para dev/staging/prod.

- **Recursos:** cluster Aurora (writer `db.serverless`), DB subnet group (en subnets **data-tier**), reglas de security group, master password gestionada en Secrets Manager.
- **Comportamiento:** `manage_master_user_password = true` (password auto-guardada en Secrets Manager). Exports de logs a CloudWatch: `audit`, `error`, `general`, `slowquery`. Ingress permitido solo desde los CIDRs de subnets privadas (más restrictivo que el CIDR de la VPC); opcionalmente desde las subnets TGW-attachment de la cuenta network cuando `enable_vpn_access = true`.
- **Quirk de restore de snapshot:** cuando se pasa `snapshot_identifier`, `database_name` y `master_username` se fuerzan a `null` (se heredan del snapshot — pasarlos da error). `engine_version` se deja en `null` para que Aurora auto-seleccione una versión compatible con el snapshot (fijar `"8.0"` puede resolver a un minor más nuevo que el origen del snapshot y fallar).

| Variable | Tipo | Default | Notas |
|----------|------|---------|-------|
| `name` | string | — | |
| `database_name` | string | `dropstat` | ignorado en restore de snapshot |
| `master_username` | string | `appuser` | ignorado en restore de snapshot |
| `db_subnet_group_name` | string | `null` | cuando es null, el módulo crea uno |
| `min_capacity` | number | `0.5` | ACU mín de Serverless v2 |
| `max_capacity` | number | `2.0` | ACU máx de Serverless v2 |
| `skip_final_snapshot` | bool | `true` | |
| `deletion_protection` | bool | `false` | |
| `copy_tags_to_snapshot` | bool | `false` | |
| `monitoring_interval` | number | `0` | enhanced monitoring |
| `performance_insights_enabled` | bool | `false` | |
| `backup_retention_period` | number | `7` | ventana `07:00-08:00` |
| `snapshot_identifier` | string | `null` | origen del restore |
| `engine_version` | string | `null` | explícito solo para snapshots de MySQL no-Aurora |
| `enable_vpn_access` | bool | `false` | requiere provider con alias `aws.network` |
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

Redis 7.1 single-node vía `terraform-aws-modules/elasticache ~> 1.0`.

- **Recursos:** cluster ElastiCache (sin replication group), SG.
- **Comportamiento:** puerto 6379, ingress desde el **CIDR de la VPC** (un único `cidr_ipv4`, porque `aws_vpc_security_group_ingress_rule` acepta un solo CIDR — cubre todas las subnets privadas sin reglas por subnet), `apply_immediately`, upgrades de minor automáticos.
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

Amazon MQ (ActiveMQ) broker single-instance — `aws_mq_broker` nativo (sin módulo oficial) + `security-group ~> 5.0`.

- **Recursos:** broker MQ, SG.
- **Comportamiento:** deployment `SINGLE_INSTANCE`; cuando no es público, se ubica en la primera subnet privada. El SG abre MQTT (1883), AMQPS (5671) y la consola web de ActiveMQ (8162) para cada SG en `allowed_security_group_ids`. Ventana de mantenimiento domingo 06:00 UTC. Logging general activo, audit apagado.
- **Inputs:** `name`, `allowed_security_group_ids` (`[]`), `instance_type` (`mq.t3.micro`), `engine_version` (`5.18`), `publicly_accessible` (`false`), `admin_username` (`dropstat`), `admin_password` (sensible, requerido), `tags`.
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

Creación de colas SQS en bloque vía `terraform-aws-modules/sqs ~> 4.0`.

- **Recursos:** una cola por entrada en `queue_names` (`for_each`), SSE gestionado por SQS activado.
- **Inputs:** `queue_names` (list(string)), `message_retention_seconds` (`345600` = 4 días), `visibility_timeout_seconds` (`30`), `tags`.
- **Outputs:** `queue_urls` (mapa nombre→url), `queue_arns` (mapa nombre→arn).

```hcl
module "queues" {
  source      = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/sqs?ref=master"
  queue_names = ["dropstat-events", "dropstat-notifications"]
}
```

---

### `workload-secrets`

Bundle de secretos por ambiente en un único secreto de Secrets Manager (`dropstat/{env}/workload`) como objeto JSON, vía `terraform-aws-modules/secrets-manager ~> 2.0`.

- **Recursos:** dos `random_password` (auto-generados), un secreto de Secrets Manager.
- **Auto-generados:** `mqtt_password` (32 caracteres, `override_special` excluye `, : =` que Amazon MQ rechaza) y `jwt_secret_key` (64 caracteres, sin especiales). Ambos con keeper de rotación.
- **Manuales:** `nursa_dropstat_password`, `nursa_dropstat_user`, `nursa_client_id`, `nursa_user_name` — sembrados con `REPLACE_ME` y luego editados directamente en Secrets Manager; el módulo pone `ignore_secret_changes = true` para que Terraform nunca los revierta. Todo el blob va envuelto en `sensitive()`. `recovery_window_in_days = 0`.
- **Inputs:** `env` (requerido), los cuatro `nursa_*` (default `REPLACE_ME`), `tags`.
- **Outputs:** `secret_arn` (usar como `secret_arn:key::`), `secret_name`, `mqtt_username` (`dropstat`), `mqtt_password` (sensible).

```hcl
module "secrets" {
  source = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/workload-secrets?ref=master"
  env    = "dev"
}
```

---

### `dns-records`

Records de Route53 en una zona **existente**, usando `aws_route53_record` nativo — sin `data` lookup, así funciona limpio cuando `zone_id` viene de una dependencia (evita "zone not found" en el primer apply).

- **Inputs:** `zone_id` (requerido), `zone_name` (solo docs), `records` (lista de `{name,type,ttl,records}`).
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

## 7. Cómo consumir estos módulos desde `dropstat-aws-workload-deploy`

El repo de deploy cablea los módulos por ambiente. Los outputs alimentan los inputs del siguiente módulo, formando el grafo de dependencias:

```
ecs-cluster ─┐
acm ─► alb ──┼─► ecs-service ◄─ workload-secrets
             └─► apigw ──► dns-records
aurora / elasticache / mq / sqs  (plano de datos, referenciados por env/secrets de ecs-service)
```

```hcl
# Fija un tag/SHA para despliegues reproducibles:
terraform {
  source = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/ecs-service?ref=v1.4.0"
}
```

Cableado típico (conceptual):

1. `acm` → ARN del certificado → `alb` y `apigw`.
2. `ecs-cluster` → `cluster_arn` / `cluster_name` → `ecs-service`.
3. `alb` → `security_group_id`, `arn_suffix`, ARNs de listener → `ecs-service`.
4. `workload-secrets` → `secret_arn` + `secret_arns` → `ecs-service` (`secrets` / permisos del rol exec) y `mqtt_password` → `mq`.
5. `apigw` → `domain_target` → `dns-records`.

> Como `ecs-service` invoca el CLI vía `data.external`, el runner de deploy necesita `aws` + `bash` en el PATH y credenciales para `us-east-2`.

---

## 8. Notas de compatibilidad con AWS provider v6

La librería fue migrada a AWS provider v6 / ECS module v6 (desde v5.12). Ajustes notables:

- **ECS service module v6:** removido `inference_accelerator` (incompatible con v6); `cloudwatch_log_group_retention_in_days` movido dentro de `container_definitions`; `tasks_iam_role_statements` pasó a ser un `list(object)`; el output del ARN del servicio ahora es `id`, no `arn`.
- **ECS cluster v6:** `cluster_setting` es una lista `[{}]`, no un objeto.
- **ALB v9:** el tipo de acción es una clave top-level del listener (`redirect`/`fixed_response`/`forward`); sin wrapper `action`.
- **apigateway-v2 v5:** integrations movidos dentro de routes; renombres de clave `type`/`uri`/`method`.
- **WAFv2:** `override_action { none {} }` y `action { block {} }` escritos multi-línea.
- **variables.tf:** forma multi-línea en todo (los separadores `;` de una sola línea son inválidos bajo el tooling de v6).

---

## 9. Patrones de security group

| Módulo | Patrón | Notas |
|--------|--------|-------|
| `ecs-service` | `ingress_with_source_security_group_id` desde el SG del ALB en `container_port`; egress `all-all` | Las tasks aceptan tráfico solo desde el ALB |
| `alb` | `security_group_ingress_rules` 80/443 desde `0.0.0.0/0`; egress `-1` a `0.0.0.0/0` | Integrado en el módulo ALB v9 |
| `apigw` (VPC Link) | `egress_with_cidr_blocks` 80/443 a `0.0.0.0/0` | El VPC Link alcanza el ALB interno |
| `aurora` | `security_group_rules` con `cidr_blocks` = CIDRs de subnets privadas (+ CIDRs TGW-attachment opcionales) | El módulo usa el legacy `aws_security_group_rule` |
| `elasticache` | `security_group_rules` con un único `cidr_ipv4` = CIDR de la VPC | El módulo usa `aws_vpc_security_group_ingress_rule` (un CIDR por regla) |
| `mq` | `ingress_with_source_security_group_id` para 1883/5671/8162 por cada SG permitido; egress `all-all` | `flatten()` sobre `allowed_security_group_ids` |

Todos los SGs usan `terraform-aws-modules/security-group ~> 5.0` excepto donde el módulo de respaldo gestiona su propio SG (ALB, Aurora, ElastiCache).
