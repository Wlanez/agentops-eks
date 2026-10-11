output "state_bucket_name" {
  description = "Generated S3 bucket name. Keep this value private."
  value       = aws_s3_bucket.state.id
  sensitive   = true
}

output "state_bucket_region" {
  description = "Region containing the Terraform state bucket."
  value       = var.aws_region
}