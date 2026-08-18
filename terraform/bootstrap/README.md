# Terraform state bootstrap

This root creates the S3 bucket that stores Terraform state for the `dev` environment.

## First Principles

**Problem:** Terraform needs durable memory of the infrastructure it manages.

**Without automation:** an operator would have to track resource IDs and configuration changes manually.

**Automation:** Terraform state records the mapping between configuration and real AWS resources. The state bucket is created once, then the `dev` environment uses it through the S3 backend.

**Why the bootstrap starts locally:** the remote state bucket cannot store Terraform state before that bucket exists. This bootstrap therefore starts with local state as a deliberate chicken-and-egg step. The application/platform environment does not share that compromise.

**Proof:** after apply, the bucket exists with versioning, encryption and public-access blocking enabled.

**Why no AI:** state management is deterministic infrastructure bookkeeping. An LLM adds no useful reasoning to this path.

## Prerequisite

Confirm the AWS identity before creating anything:

```bash
aws sts get-caller-identity
```

## Create the state bucket

From the repository root:

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap fmt -check
terraform -chdir=terraform/bootstrap validate
terraform -chdir=terraform/bootstrap plan
terraform -chdir=terraform/bootstrap apply
```

The bucket name is deterministic:

```text
agentops-eks-tfstate-<aws-account-id>-<region>
```

Display the values needed by the dev backend:

```bash
terraform -chdir=terraform/bootstrap output
```

The `dev_backend_init_command` output is copyable from the repository root.

## State protection

The bucket uses:

- S3 Versioning for recovery from accidental state overwrite/deletion.
- AES256 server-side encryption.
- S3 Block Public Access.
- Bucket-owner-enforced object ownership.
- Terraform `prevent_destroy` so a normal destroy cannot accidentally remove the state bucket.

The dev backend uses native S3 lock files (`use_lockfile = true`) rather than the deprecated DynamoDB locking path.

## Teardown note

The state bucket is intentionally protected from normal `terraform destroy`. Deleting the bootstrap requires an explicit decision to remove `prevent_destroy` and ensure no environment still depends on the bucket.
