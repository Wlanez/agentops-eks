# Development Terraform root

This root will own v0.1 VPC, EKS, ECR, and supporting resources in later workstreams.

At this stage it contains only a built-in `terraform_data` contract. This creates no AWS infrastructure and proves remote state before expensive resources are introduced.

## Initialize safely

1. Authenticate with `agentops-lab-bootstrap`.
2. Run `scripts/aws-terraform-preflight.sh`.
3. Resolve the private bucket name from bootstrap.
4. Initialize with the bucket passed through `-backend-config`.
5. Run tests, validation, a saved plan, and review before apply.

The key is `environments/dev/terraform.tfstate` and native S3 locking is mandatory.

Never use `-lock=false` or commit the bucket name, state, binary plans, or `.terraform/`.