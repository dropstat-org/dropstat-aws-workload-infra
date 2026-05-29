output "api_id"          { value = module.apigw.api_id }
output "api_endpoint"    { value = module.apigw.api_endpoint }
output "stage_arn"       { value = module.apigw.stage_arn }
output "domain_name"     { value = try(module.apigw.domain_name, null) }
output "domain_target"   { value = try(module.apigw.domain_name_target_domain_name, null) }
output "waf_arn"         { value = try(aws_wafv2_web_acl.this[0].arn, null) }
