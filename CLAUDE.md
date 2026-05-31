# dropstat-aws-workload-infra

**Librería de módulos Terraform** para la capa de workload de Dropstat.
Este repo contiene SOLO módulos (`_modules/`) — no tiene `live/` ni Terragrunt configs.
Los despliegues reales viven en `dropstat-aws-workload-deploy`.

**Visibilidad:** Público (módulos Terraform no tienen secretos).

---

## Arquitectura de módulos

```
dropstat-aws-workload-infra/  ← módulos Terraform (público)
└── _modules/
    ├── alb/          ← ALB interno via terraform-aws-modules/alb ~> 9.0
    ├── apigw/        ← API Gateway HTTP v2 via terraform-aws-modules/apigateway-v2 ~> 5.0
    ├── aurora/       ← Aurora Serverless v2 via terraform-aws-modules/rds-aurora ~> 9.0
    ├── dns-records/  ← Route53 records via terraform-aws-modules/route53 (módulo records)
    ├── ecs-cluster/  ← ECS cluster via terraform-aws-modules/ecs ~> 6.0
    ├── ecs-service/  ← ECS Fargate service via terraform-aws-modules/ecs//modules/service ~> 6.0
    ├── elasticache/  ← Redis via terraform-aws-modules/elasticache ~> 1.0
    ├── mq/           ← Amazon MQ (ActiveMQ) — recursos nativos (sin módulo oficial)
    └── sqs/          ← SQS queues via terraform-aws-modules/sqs ~> 4.0
```

---

## Premisa de diseño — terraform-aws-modules first

**Todos los módulos usan `terraform-aws-modules` donde existe módulo oficial.**
Recursos sueltos (`resource "aws_*"`) solo cuando no hay alternativa.

| Módulo | Estado |
|--------|--------|
| `alb` | ✅ terraform-aws-modules/alb v9 |
| `apigw` | ✅ terraform-aws-modules/apigateway-v2 v5. WAF: recursos nativos (sin módulo oficial) |
| `aurora` | ✅ terraform-aws-modules/rds-aurora v9 |
| `ecs-cluster` | ✅ terraform-aws-modules/ecs v6 |
| `ecs-service` | ✅ terraform-aws-modules/ecs//modules/service v6 + security-group module |
| `elasticache` | ✅ terraform-aws-modules/elasticache v1 |
| `mq` | ✅ aws_mq_broker nativo (sin módulo), SG via security-group module |
| `sqs` | ✅ terraform-aws-modules/sqs v4 |

---

## Descubrimiento dinámico de VPC/Subnets — tm-aws-account-data

**Cada módulo** que necesita VPC/subnets tiene embebido `module "account"` que llama a `tm-aws-account-data`. Esto elimina la necesidad de pasar vpc_id/subnet_ids como variables — los módulos los descubren por tags en AWS al momento del plan/apply.

```hcl
# Patrón en cada módulo que necesita VPC
module "account" {
  source = "git::https://github.com/dropstat-org/tm-aws-account-data.git?ref=master"
}
# Uso: module.account.vpc.id, module.account.subnets.privates[*].id
```

Módulos con descubrimiento embebido: `alb`, `apigw`, `aurora`, `elasticache`, `mq`, `ecs-service`

---

## Cambios importantes aplicados

### ECS module v6 (upgrade de v5.12)
- Removido `inference_accelerator` — incompatible con AWS provider v6
- `cloudwatch_log_group_retention_in_days` → dentro de `container_definitions` (no top-level)
- `tasks_iam_role_statements` → `list(object)` en lugar de `map` (conversión automática en módulo)
- `cluster_setting` → lista `[{}]` en lugar de objeto `{}`
- Output `arn` → renombrado a `id` para el service ARN

### ALB module v9
- `listeners` usa action type como atributo top-level (`redirect`, `fixed_response`) — no hay `action` wrapper
- Listener rule condicional: `count = local.listener_arn != null ? 1 : 0` — soporta estado inicial sin ALB

### Security groups
- Todos usan `terraform-aws-modules/security-group ~> 5.0`
- `source_security_group_id` para aurora (módulo usa recurso legacy `aws_security_group_rule`)
- `referenced_security_group_id` para elasticache (módulo usa `aws_vpc_security_group_ingress_rule`)

### AWS provider v6 compatibility
- `variables.tf`: expandidos a multi-línea (semicolons inválidos en v6)
- WAF: `override_action { none {} }` y `action { block {} }` → multi-línea
- apigateway-v2 v5: `integrations` + `routes` → routes con `integration` inline

---

## Referencia de módulos externos usados

| Módulo | Versión | Registry |
|--------|---------|----------|
| terraform-aws-modules/alb | ~> 9.0 | https://registry.terraform.io/modules/terraform-aws-modules/alb/aws |
| terraform-aws-modules/apigateway-v2 | ~> 5.0 | https://registry.terraform.io/modules/terraform-aws-modules/apigateway-v2/aws |
| terraform-aws-modules/rds-aurora | ~> 9.0 | https://registry.terraform.io/modules/terraform-aws-modules/rds-aurora/aws |
| terraform-aws-modules/ecs | ~> 6.0 | https://registry.terraform.io/modules/terraform-aws-modules/ecs/aws |
| terraform-aws-modules/elasticache | ~> 1.0 | https://registry.terraform.io/modules/terraform-aws-modules/elasticache/aws |
| terraform-aws-modules/security-group | ~> 5.0 | https://registry.terraform.io/modules/terraform-aws-modules/security-group/aws |
| terraform-aws-modules/sqs | ~> 4.0 | https://registry.terraform.io/modules/terraform-aws-modules/sqs/aws |
| terraform-aws-modules/route53 | ~> 4.0 | https://registry.terraform.io/modules/terraform-aws-modules/route53/aws |
| tm-aws-account-data | master | https://github.com/dropstat-org/tm-aws-account-data |

---

## Cómo consumir los módulos (desde dropstat-aws-workload-deploy)

```hcl
# En cualquier terragrunt.hcl del deploy repo:
terraform {
  source = "github.com/dropstat-org/dropstat-aws-workload-infra//_modules/ecs-service?ref=master"
}
```

La rama `master` es la rama principal. Los módulos se referencian por `?ref=master` — sin PAT ni autenticación (repo público).
