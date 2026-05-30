# dropstat-aws-workload-infra

IaC para la capa de workload de Dropstat. Define la infraestructura de ECS, Aurora, Redis, MQ, SQS, ALB y API Gateway. **No contiene pipelines de deploy de imágenes** — eso vive en cada repo de servicio.

---

## Premisa de diseño — terraform-aws-modules first

**Todos los módulos deben usar `terraform-aws-modules` donde exista un módulo oficial.**
Referencia de módulos disponibles: https://github.com/orgs/terraform-aws-modules/repositories

Recursos sueltos (`resource "aws_*"`) solo se permiten cuando:
1. No existe módulo oficial para ese servicio (ej. Amazon MQ → `aws_mq_broker`)
2. El módulo oficial no expone el recurso necesario y no hay workaround limpio

Security groups en particular deben usar `terraform-aws-modules/security-group/aws` en lugar de `resource "aws_security_group"` suelto.

### Estado actual de cumplimiento

| Módulo | Estado | Módulo TF a usar |
|--------|--------|------------------|
| `alb` | ✅ usa `terraform-aws-modules/alb/aws` | — |
| `ecs-cluster` | ✅ usa `terraform-aws-modules/ecs/aws` | — |
| `ecs-service` | ⚠️ parcial — SG migrado a `security-group` module. Pendiente: `aws_lb_target_group`, `aws_lb_listener_rule` (patrón dinámico por servicio, sin módulo que encaje), `aws_appautoscaling_*` (sin módulo oficial) | Sueltos restantes justificados |
| `aurora` | ✅ usa `terraform-aws-modules/rds-aurora/aws` | — |
| `elasticache` | ✅ usa `terraform-aws-modules/elasticache/aws` | — |
| `sqs` | ✅ usa `terraform-aws-modules/sqs/aws` | — |
| `apigw` | ⚠️ parcial — `module.apigw` usa TF modules pero `aws_security_group`, `aws_wafv2_web_acl`, `aws_wafv2_web_acl_association` son recursos sueltos | `terraform-aws-modules/security-group/aws`, `terraform-aws-modules/wafv2/aws` |
| `mq` | ✅ justificado — no existe módulo oficial para Amazon MQ | recursos nativos aceptados |
| `dns-records` | — pendiente revisar | — |

---

## Repositorios relacionados

| Repo | Qué hace |
|------|----------|
| `dropstat-org/dropstat-aws-workload-infra` | **Este repo** — IaC de workload (ECS cluster, ALB, API GW, Aurora, Redis, MQ, SQS) |
| `dropstat-org/platform-infra` | IaC de plataforma (Organizations, SCPs, VPC, TGW, Identity Center, ECR) |
| `dropstat-org/dropstat-api` | Servicio Java — compile + test + publish + deploy ECS |
| `dropstat-org/integrations-rest` | Servicio Python — compile + test + publish + deploy ECS |
| `dropstat-org/nursa` | Servicio Java — compile + test + publish + deploy ECS |

---

## Arquitectura de red

```
Internet
  └── API Gateway HTTP v2  (WAF adjunto en prod)
       └── VPC Link (private subnets)
            └── ALB interno (private subnets — no internet-facing)
                 ├── /api/*          → ECS dropstat-api
                 ├── /integrations/* → ECS integrations-rest
                 └── /nursa/*        → ECS nursa
                      └── Aurora Serverless v2  (data subnets)
                      └── ElastiCache Redis     (data subnets)
                      └── Amazon MQ             (private subnets)
                      └── SQS queues
```

### Por qué ALB interno + API Gateway

- Las cuentas workload (dev/prod) **no tienen subnets públicas** — solo la cuenta `network` tiene egress VPC con NAT y subnets públicas. Esto sigue el modelo hub-and-spoke de AWS Control Tower / AFT.
- API Gateway es internet-facing (managed por AWS, no necesita subnets) y se conecta al ALB interno via **VPC Link**.
- WAF adjunto a API GW cubre todos los servicios a la vez (OWASP, rate limiting, IP reputation).

### Subnets por capa

| Capa | Tag `subnet-type` | Qué vive aquí |
|------|-------------------|---------------|
| `workload` | `workload` | ECS tasks, MQ, ALB |
| `data` | `data` | Aurora, ElastiCache |
| `secu` | `secu` | TGW attachment ENIs |

Descubierto automáticamente por `tm-aws-account-data` — sin IDs hardcodeados.

---

## Estructura del repo

```
dropstat-aws-workload-infra/
├── CLAUDE.md
├── common_vars.yaml          ← ECR registry, repo names, MQ engine
├── terragrunt.hcl            ← root: remote state + provider
│
├── _modules/                 ← módulos Terraform reutilizables
│   ├── ecs-cluster/          ← ECS cluster (container insights on/off)
│   ├── ecs-service/          ← ECS service + target group + ALB rule + AppAutoScaling
│   ├── alb/                  ← ALB interno, host-based routing
│   ├── apigw/                ← API Gateway HTTP v2 + VPC Link + WAF
│   ├── aurora/               ← Aurora Serverless v2 MySQL 8.0
│   ├── elasticache/          ← ElastiCache Redis
│   ├── mq/                   ← Amazon MQ (ActiveMQ)
│   └── sqs/                  ← SQS queues
│
└── live/
    └── dev/                  ← cuenta dev (453531893227)
        ├── env.hcl           ← sizing, config, hostnames, image tags
        ├── _shared/          ← recursos compartidos por todos los servicios
        │   ├── account-data/ ← VPC + subnets via tm-aws-account-data
        │   ├── ecs-cluster/  ← un cluster para todos los servicios
        │   ├── alb/          ← un ALB para todos los servicios
        │   └── apigw/        ← un API GW con VPC Link + WAF
        ├── ecs/
        │   ├── dropstat-api/
        │   ├── integrations-rest/
        │   └── nursa/
        ├── storage/
        │   ├── aurora/
        │   ├── elasticache/
        │   └── sqs/
        └── messaging/
            └── mq/
```

---

## Módulo `tm-aws-account-data`

**Repo:** `dropstat-org/tm-aws-account-data` (`v1.0.0`)

Descubre la VPC y subnets del account actual por tags — sin remote state ni IDs hardcodeados. Todos los módulos hacen `dependency` sobre `_shared/account-data`.

```hcl
# Uso en cualquier terragrunt.hcl
dependency "account" {
  config_path = "../../_shared/account-data"
}

inputs = {
  vpc_id             = dependency.account.outputs.vpc_id
  private_subnet_ids = dependency.account.outputs.private_subnet_ids  # ECS, MQ, ALB
  data_subnet_ids    = dependency.account.outputs.data_subnet_ids      # Aurora, Redis
}
```

---

## Auto-scaling ECS — scale-to-zero

Todos los servicios ECS usan `ALBRequestCountPerTarget` como métrica de scaling (no CPU, que no puede bajar a 0):

| Config | Dev | Prod |
|--------|-----|------|
| `min_task_count` | `0` — scale to zero cuando idle | `1` — siempre disponible |
| `max_task_count` | `2-3` | según carga |
| `scaling_target_value` | `10` req/min/target | ajustar según tráfico |
| `scale_in_cooldown` | `300s` — evita flapping | `300s` |
| `scale_out_cooldown` | `60s` — respuesta rápida | `60s` |

> **Cold start en dev:** escalar de 0 → 1 tarda ~30-60s en Fargate. Aceptable en dev, no en prod.

---

## Configuración por ambiente — `env.hcl`

Cada ambiente tiene su propio `env.hcl`. Los módulos son **idénticos** entre dev y prod, solo cambian los valores:

```
live/dev/env.hcl   ← ya existe
live/prod/env.hcl  ← por crear
```

### Diferencias clave dev vs prod

| Campo | Dev | Prod |
|-------|-----|------|
| `min_task_count` | `0` | `1` |
| `container_insights_enabled` | `false` | `true` |
| `certificate_arn` | `null` (HTTP) | ARN real de ACM |
| `apigw.waf_enabled` | `false` | `true` |
| `apigw.domain_name` | `null` | `api.dropstat.com` |
| `aurora.skip_final_snapshot` | `true` | `false` |
| `aurora.deletion_protection` | `false` | `true` |
| `aurora.monitoring_interval` | `0` | `60` |
| `aurora.performance_insights_enabled` | `false` | `true` |
| `aurora.max_capacity` | `2.0 ACU` | revisar según carga |
| `log_retention_days` | `7` | `30` |

---

## Deploy de servicios — cómo funciona

> **Este repo NO se toca en un deploy normal.** Un deploy de código es solo actualizar la imagen en ECS.

### Flujo completo (rama `develop`)

```
Push a develop (en repo del servicio)
  └── opscore.yml (gha-actions-core-lib)
       ├── compile        → build artefacto
       ├── unit_test      → tests
       ├── trivy          → scan de vulnerabilidades
       ├── publish        → build imagen + push ECR tag sha-xxxxxxx
       ├── release        → promueve sha-xxx → :dev en ECR
       └── deploy-dev     → deploy automático a dev (sin aprobación)
            ├── aws-actions/amazon-ecr-login@v2
            ├── aws-actions/amazon-ecs-render-task-definition@v1
            │   └── inyecta nuevo image URI en task-def.json
            └── aws-actions/amazon-ecs-deploy-task-definition@v2
                └── registra nueva task def + rolling update ECS
```

### Deploy manual a prod (workflow_dispatch)

```
deploy.yml (manual, con aprobación)
  ├── validate-confirm  → escribir "deploy" para confirmar
  ├── validate-approver → verificar que el actor tiene permiso (gw-devops)
  └── deploy → mismos pasos que dev, apuntando a cluster prod
```

### API Gateway — no necesita deploy de código

API GW queda fijo (creado por Terraform). Solo cambia cuando hay cambios de infra (nuevas rutas, throttling, WAF). El deploy de código solo actualiza ECS — API GW no se toca.

| Cambio | Quién lo maneja |
|--------|----------------|
| Nueva imagen Docker | Deploy workflow en repo del servicio |
| Nueva ruta en API GW | PR en este repo (Terraform) |
| Cambio de throttling | PR en este repo |
| Cambio de variables de entorno | PR en este repo (env.hcl) |

### Cada servicio tiene en su repo

```
dropstat-api/
├── task-def.json          ← task definition base (sin imagen — la inyecta render action)
├── action.yaml            ← stages para gha-actions-core-lib
└── .github/workflows/
    ├── opscore.yml        ← CI + auto-deploy a dev en push a develop
    └── deploy.yml         ← deploy manual a prod con aprobación
```

---

## Orden de apply (primera vez)

```
1. _shared/account-data    → solo lee, no crea recursos
2. _shared/ecs-cluster     → cluster ECS
3. _shared/alb             → ALB interno
4. storage/aurora          → Aurora Serverless v2
5. storage/elasticache     → Redis
6. storage/sqs             → queues
7. messaging/mq            → Amazon MQ
8. ecs/dropstat-api        → ECS service + target group + ALB rule
9. ecs/integrations-rest   → ídem
10. ecs/nursa              → ídem
11. _shared/apigw          → API GW + VPC Link + WAF (depende de ALB listener)
```

> Después del primer apply de aurora, actualizar `ecs_security_group_id` en `storage/aurora/terragrunt.hcl` y `storage/elasticache/terragrunt.hcl` con el SG real de ECS.

---

## Remote state

```
Bucket:  dropstat-tfstate-174917982419
Region:  us-east-2
Key:     {path_relative_to_include}/terraform.tfstate
Lock:    dropstat-tfstate-lock (DynamoDB)
```

---

## TODOs pendientes

- [ ] Crear `live/prod/env.hcl`
- [ ] Actualizar `ecs_security_group_id` en aurora + elasticache tras primer apply
- [ ] Configurar `certificate_arn` en `env.hcl` cuando ACM esté listo
- [ ] Habilitar `waf_enabled = true` en prod env.hcl
- [ ] Crear `task-def.json` en cada repo de servicio
- [ ] Crear `opscore.yml` + `deploy.yml` en cada repo de servicio
- [ ] Route 53: zona pública en management + zona privada en shared-services
