
# Terraform roots

This project uses explicit root directories instead of Terraform workspaces.

| Root | State key | Responsibility |
|---|---|---|
| bootstrap | bootstrap/terraform.tfstate | S3 backend and protection controls |
| environments/dev | environments/dev/terraform.tfstate | v0.1 resources added in later workstreams |

Always authenticate through IAM Identity Center and run `scripts/aws-terraform-preflight.sh` before Terraform.

The bootstrap root initially uses local state only long enough to create and verify S3. Its state is then migrated. Normal dev teardown never targets bootstrap.

Never commit or publish state, binary plans, backend caches, real bucket names, account identifiers, ARNs, or credentials.
