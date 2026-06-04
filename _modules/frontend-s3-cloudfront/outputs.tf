output "bucket_name" {
  description = "S3 bucket name — used in: aws s3 sync dist/ s3://{bucket_name}/"
  value       = module.s3.s3_bucket_id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.s3.s3_bucket_arn
}

output "distribution_id" {
  description = "CloudFront distribution ID — used in: aws cloudfront create-invalidation --distribution-id {id}"
  value       = module.cloudfront.cloudfront_distribution_id
}

output "distribution_domain" {
  description = "CloudFront domain name (e.g. d2c9jfizgif3kh.cloudfront.net)"
  value       = module.cloudfront.cloudfront_distribution_domain_name
}

output "distribution_arn" {
  description = "CloudFront distribution ARN"
  value       = module.cloudfront.cloudfront_distribution_arn
}
