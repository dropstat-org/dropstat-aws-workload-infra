# ============================================================
# _modules/route53-zone
#
# Creates a PRIVATE Route53 hosted zone and associates it
# with the workload VPC. Used for internal service discovery.
#
# Why private (not public):
#   - Internal records (ALB, Aurora, Redis) must NOT be visible
#     on the public internet — leaks topology info
#   - Resolves only from within the associated VPC
#   - Standard AWS best practice for service-to-service DNS
#
# Naming convention: {cloud}.{company}.internal
#   aws.dropstat.internal  → all resources in AWS
#   (future) gcp.dropstat.internal → if GCP is added
#
# Uses: terraform-aws-modules/route53/aws ~> 4.0
# ============================================================

variable "zone_name" {
  type        = string
  description = "DNS zone name, e.g. aws.dropstat.internal"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to associate with the private zone"
}

variable "vpc_region" {
  type        = string
  description = "AWS region of the VPC"
  default     = "us-east-2"
}

variable "comment" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "force_destroy" {
  type        = bool
  default     = true
  description = "Whether to delete all records in the zone when destroying it. Needed when recreating the zone (e.g. zone name change)."
}

module "zones" {
  source  = "terraform-aws-modules/route53/aws//modules/zones"
  version = "~> 4.0"

  zones = {
    (var.zone_name) = {
      comment       = var.comment != "" ? var.comment : "Private zone for internal service discovery — ${var.zone_name}"
      force_destroy = var.force_destroy

      # Private zone — only resolvable from within the VPC
      vpc = [
        {
          vpc_id     = var.vpc_id
          vpc_region = var.vpc_region
        }
      ]

      tags = var.tags
    }
  }
}

output "zone_id" {
  description = "Route53 zone ID"
  value       = module.zones.route53_zone_zone_id[var.zone_name]
}

output "zone_name" {
  description = "Zone name"
  value       = var.zone_name
}

output "name_servers" {
  description = "Name servers for the zone (for reference only — private zones don't need NS delegation)"
  value       = module.zones.route53_zone_name_servers[var.zone_name]
}
