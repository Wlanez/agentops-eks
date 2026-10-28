# Terraform backend bootstrap

This root owns only the protected S3 backend.

## Why the first apply is local

Terraform cannot use S3 before the bucket exists. The initial configuration therefore has no `backend.tf` and uses temporary local state.

## Safe order

1. Authenticate with `agentops-lab-bootstrap`.
2. Run preflight.
3. Run format, tests, validation, and a saved plan.
4. Verify the six-resource allowlist.
5. Obtain human approval.
6. Apply the saved plan.
7. Read back all controls.
8. Add `backend.tf` separately.
9. Migrate bootstrap state.
10. Verify remote state before removing a local backup.

Stop on an unexpected account, role, region, resource type, bucket inventory, migration prompt, or failed readback.

Do not run normal destroy against this root. Deliberate teardown requires backups, local migration, reviewed guard removal, version deletion, and separate approval.