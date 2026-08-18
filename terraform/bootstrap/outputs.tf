output "state_bucket_name" {
  description = "S3 bucket used by the dev environment Terraform backend."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "state_region" {
  description = "AWS region containing the Terraform state bucket."
  value       = data.aws_region.current.name
}

output "dev_backend_init_command" {
  description = "Example command to initialize the dev environment with the remote backend."
  value       = "terraform -chdir=terraform/environments/dev init -backend-config=\"bucket=${aws_s3_bucket.terraform_state.bucket}\" -backend-config=\"region=${data.aws_region.current.name}\""
}
