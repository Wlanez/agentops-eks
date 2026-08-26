# Terraform State Bootstrap Evidence

**Completed controls:** 2026-08-25  
**Region:** us-west-2  
**Status:** Final verification pending

## Verified controls

- [x] Terraform ran through the intended lab bootstrap identity after its preflight guard passed.
- [x] The state bucket was created by Terraform, not by the AWS console.
- [x] The bucket uses a generated name and that name is not recorded in this evidence.
- [x] S3 versioning is enabled.
- [x] Default SSE-S3 encryption uses AES256.
- [x] All four S3 public-access blocks are enabled.
- [x] ACLs are disabled with Bucket Owner Enforced.
- [x] The bucket policy denies non-TLS transport.
- [x] Force deletion is disabled and ordinary Terraform destruction is guarded.
- [x] Bootstrap state was migrated from temporary local state to S3.
- [x] Bootstrap and dev have separate S3 backend keys with native S3 lockfiles configured.
- [x] The reviewed dev plan contains only the cost-free `terraform_data` backend contract.
- [x] DynamoDB locking is not configured.
- [x] Repository privacy checks found no account identifiers, credentials, keys, or bucket name in tracked files.

## Pending final verification

- [ ] Read back the bucket controls from AWS with `scripts/verify-state-bucket.sh`.
- [ ] Apply and read back the dev backend contract from its remote state.
- [ ] Confirm both remote states are readable and final plans report no drift.
- [ ] Remove ignored local bootstrap state remnants only after the remote-state readback succeeds.

## Cost boundary

This workstream creates one small S3 bucket and no EKS, EC2, NAT gateway, load balancer, KMS key, DynamoDB table, or application resource. The dev contract is a Terraform state-only resource and creates no AWS workload resource.

## Credential model

Human execution uses temporary AWS IAM Identity Center credentials. No long-lived AWS access keys are used.

## Privacy

Account IDs, bucket names, ARNs, emails, portal URLs, state contents, tokens, credentials, and local personal paths are intentionally excluded.
