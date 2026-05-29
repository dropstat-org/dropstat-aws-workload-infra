include "root" {
  path   = find_in_parent_folders()
  expose = true
}

locals {
  env    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
  suffix = local.env.locals.queue_suffix  # "-dev"
}

terraform {
  source = "../../../../_modules/sqs"
}

inputs = {
  # Appends -dev suffix to all queue names
  queue_names = [for q in local.common.sqs_queues : "${q}${local.suffix}"]

  message_retention_seconds  = 345600  # 4 days
  visibility_timeout_seconds = 30
}
