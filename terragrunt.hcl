# ============================================================
# dropstat-aws-workload-infra — Root terragrunt.hcl
# Reads environment from live/{env}/env.hcl
# State bucket: management account (174917982419)
# ============================================================

locals {
  env         = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  common_vars = yamldecode(file(find_in_parent_folders("common_vars.yaml")))
}

remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    bucket         = "dropstat-tfstate-174917982419"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-2"
    encrypt        = true
    dynamodb_table = "dropstat-tfstate-lock"
  }
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.28"
    }
  }
}

provider "aws" {
  region = "us-east-2"

  %{if local.env.locals.role_arn != ""}
  assume_role { role_arn = "${local.env.locals.role_arn}" }
  %{endif}

  default_tags {
    tags = {
      ManagedBy   = "terraform"
      Project     = "dropstat"
      Environment = "${local.env.locals.account_name}"
      Repo        = "dropstat-aws-workload-infra"
    }
  }
}
EOF
}
