# Terraform State Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create and verify a protected S3 remote-state foundation in `agentops-lab`, migrate the bootstrap state into it, and prove a separate `dev` state contract without creating workload infrastructure.

**Architecture:** A dedicated Terraform root at `terraform/bootstrap` first creates the state bucket with temporary local state. After AWS readback succeeds, a partial S3 backend is added and that state is migrated to `bootstrap/terraform.tfstate`. A separate `terraform/environments/dev` root uses `environments/dev/terraform.tfstate` and a cost-free built-in `terraform_data` resource to prove remote persistence.

**Tech Stack:** Terraform 1.10+ (implementation target 1.15.x), HashiCorp AWS Provider 6.61.x, AWS CLI v2 with IAM Identity Center, Amazon S3, Bash, Python 3.

**Spec:** `docs/superpowers/specs/2026-08-25-terraform-state-bootstrap-design.md`

## Global Constraints

- Target AWS account: the `agentops-lab` member account only.
- Target human role: `AgentOpsBootstrapAdmin` through profile `agentops-lab-bootstrap`.
- Management profile `agentops-org-admin` is used only for a private account-separation comparison.
- AWS region: `us-west-2`.
- No IAM user, access key, secret key, session token, or credential file is created.
- No account ID, role ARN, bucket name, email, SSO portal URL, state content, plan content, or credential is committed or pasted into evidence.
- No VPC, subnet, NAT gateway, EKS, EC2, ECR, load balancer, KMS key, DynamoDB table, or application resource is created.
- Native S3 locking uses `use_lockfile = true`. DynamoDB locking is prohibited.
- The state bucket uses versioning, SSE-S3, all four public-access blocks, Bucket Owner Enforced, a TLS-only policy, `force_destroy = false`, and lifecycle destroy guards.
- The first bootstrap apply is local-state only. `terraform/bootstrap/backend.tf` must not exist until the bucket passes AWS readback.
- No `apply` is run from an unreviewed plan.
- Stop on an unexpected profile, account, role, region, resource type, existing project-prefix bucket, multiple project-prefix buckets, authentication failure, or privacy-scan match.
- Destructive bootstrap teardown is not part of implementation. It requires a separate approved procedure.

## Shell execution contract

All multi-command shell blocks in this plan target Bash. On macOS, where the interactive shell is commonly zsh, start a child Bash session from the repository root before running a task block:

```bash
bash
set -euo pipefail
```

Run the complete block inside that Bash child. A failed `test` may close the child Bash when `set -e` is active, but it must not close the parent terminal. Do not paste fragments containing Bash-only array syntax into zsh. Keep one Bash child open while a task depends on exported values such as `STATE_BUCKET_NAME`; a variable exported inside `bash -c '...'` does not propagate back to the parent shell.

Expected failures in RED test steps are intentional. Continue to the matching implementation step only when the failure reason is exactly the missing script or resource named by the plan.

## Files Created or Modified

- Create: `.gitignore` — prevent Terraform runtime artifacts and local inputs from entering Git.
- Create: `scripts/aws-terraform-preflight.sh` — fail closed on wrong credentials, role, account, or region.
- Create: `scripts/verify-bootstrap-plan.py` — allowlist the six S3 resource types in the reviewed plan.
- Create: `scripts/verify-state-bucket.sh` — read back bucket controls without printing private values.
- Create: `tests/terraform/test-aws-terraform-preflight.sh` — mock AWS CLI safety tests.
- Create: `tests/terraform/test_verify_bootstrap_plan.py` — plan-verifier unit tests.
- Create: `tests/terraform/test-verify-state-bucket.sh` — mock S3 readback tests.
- Create: `terraform/README.md` — explain state roots and the safe operating order.
- Create: `terraform/bootstrap/README.md` — explain initial creation, migration, recovery, and stop conditions.
- Create: `terraform/bootstrap/versions.tf`
- Create: `terraform/bootstrap/providers.tf`
- Create: `terraform/bootstrap/variables.tf`
- Create: `terraform/bootstrap/main.tf`
- Create: `terraform/bootstrap/outputs.tf`
- Create later: `terraform/bootstrap/backend.tf` — only after the bucket exists and passes readback.
- Generate and commit: `terraform/bootstrap/.terraform.lock.hcl`.
- Create: `terraform/bootstrap/tests/bootstrap.tftest.hcl`.
- Create: `terraform/environments/dev/README.md`
- Create: `terraform/environments/dev/versions.tf`
- Create: `terraform/environments/dev/backend.tf`
- Create: `terraform/environments/dev/main.tf`
- Create: `terraform/environments/dev/outputs.tf`
- Create: `terraform/environments/dev/tests/backend_contract.tftest.hcl`
- Create after all verification: `docs/evidence/v0.1/terraform-state-bootstrap.md`.

---

### Task 1: Establish the local tool and identity safety checkpoint

**Files:** None.

**Interfaces:**
- Consumes: the three verified AWS SSO profiles from the identity bootstrap.
- Produces: `tool_identity_checkpoint=PASS` and a shell with no static AWS credential variables.

- [ ] **Step 1: Start from the repository root and inspect local changes**

Run:

```bash
git status --short
git branch --show-current
git log -1 --oneline
```

Expected:

- the current repository is `agentops-eks`;
- unrelated local changes are identified before implementation;
- execution occurs in the isolated branch/worktree selected by the execution skill, not directly on `main`.

Do not discard, reset, or overwrite pre-existing changes.

- [ ] **Step 2: Verify required tools**

Run:

```bash
git --version
aws --version
terraform version
python3 --version
```

Then verify Terraform's minimum version:

```bash
terraform version -json | python3 -c '
import json
import sys

version = json.load(sys.stdin)["terraform_version"].split("-")[0]
parts = tuple(int(part) for part in version.split(".")[:2])

if parts < (1, 10):
    raise SystemExit("terraform_version_check=FAIL_REQUIRES_1_10_OR_NEWER")

print("terraform_version_check=PASS")
'
```

Expected: `terraform_version_check=PASS`.

The project targets Terraform 1.15.x, but 1.10 is the hard minimum because native S3 lockfiles are required. Stop and upgrade Terraform if this fails.

- [ ] **Step 3: Remove static credential variables from this shell**

Run:

```bash
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_SECURITY_TOKEN
```

This does not delete a credential file. It prevents environment credentials from silently taking precedence over IAM Identity Center.

- [ ] **Step 4: Refresh both SSO sessions used by the checkpoint**

Run:

```bash
aws sso login --profile agentops-lab-bootstrap
aws sso login --profile agentops-org-admin
```

Complete browser authentication as `jorge.nunez`. Both profiles are required because the next step privately compares the lab and management accounts. If either session expires later, refresh both and rerun the preflight; never bypass an authentication failure.

- [ ] **Step 5: Compare identities without printing IDs or ARNs**

Run:

```bash
set -e

LAB_ACCOUNT="$(aws sts get-caller-identity \
  --profile agentops-lab-bootstrap \
  --query Account \
  --output text)"

ORG_ACCOUNT="$(aws sts get-caller-identity \
  --profile agentops-org-admin \
  --query Account \
  --output text)"

LAB_ARN="$(aws sts get-caller-identity \
  --profile agentops-lab-bootstrap \
  --query Arn \
  --output text)"

LAB_REGION="$(aws configure get region \
  --profile agentops-lab-bootstrap)"

test "$LAB_ACCOUNT" != "$ORG_ACCOUNT"

case "$LAB_ARN" in
  *AgentOpsBootstrapAdmin*) ;;
  *) exit 1 ;;
esac

test "$LAB_REGION" = "us-west-2"

echo "tool_identity_checkpoint=PASS"

unset LAB_ACCOUNT
unset ORG_ACCOUNT
unset LAB_ARN
unset LAB_REGION
```

Expected: `tool_identity_checkpoint=PASS`.

Stop if PASS is absent. Do not print the variables to debug them in chat or GitHub.

- [ ] **Step 6: Prove the project bucket prefix is unused before bootstrap**

Run:

```bash
INITIAL_BUCKET_COUNT="$(
  aws s3api list-buckets \
    --profile agentops-lab-bootstrap \
    --query "length(Buckets[?starts_with(Name, 'agentops-eks-tfstate-')])" \
    --output text
)"

test "$INITIAL_BUCKET_COUNT" = "0"
echo "initial_project_bucket_inventory=PASS"
unset INITIAL_BUCKET_COUNT
```

Expected: `initial_project_bucket_inventory=PASS`.

This check prints only the count result. Stop if any matching bucket already exists. Do not reuse, import, rename, or delete an unexpected bucket during this workstream; investigate it separately first.

### Task 2: Add repository protections for Terraform artifacts

**Files:**
- Create: `.gitignore`

**Interfaces:**
- Consumes: repository root.
- Produces: Git exclusions for state, caches, plans, variable files, and overrides while preserving dependency lock files.

- [ ] **Step 1: Create `.gitignore`**

Use `apply_patch` to create:

```gitignore
# Terraform working directories
**/.terraform/*

# Terraform state
*.tfstate
*.tfstate.*

# Terraform crash logs
crash.log
crash.*.log

# Local variable values
*.tfvars
*.tfvars.json
!*.example.tfvars

# Saved binary plans
*.tfplan
*.plan

# Local backend configuration
*.backend.hcl

# Local override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Terraform CLI configuration
.terraformrc
terraform.rc

# Local operating-system metadata
.DS_Store

# Python test/runtime caches
__pycache__/
*.py[cod]
```

Do not ignore `.terraform.lock.hcl`. It contains provider selections and checksums, not credentials or state.

- [ ] **Step 2: Verify sensitive artifacts are ignored**

Run:

```bash
printf '%s\n' \
  'terraform/bootstrap/.terraform/provider-cache' \
  'terraform/bootstrap/terraform.tfstate' \
  'terraform/bootstrap/terraform.tfstate.backup' \
  'terraform/bootstrap/bootstrap.tfplan' \
  'terraform/bootstrap/private.auto.tfvars' \
  'terraform/bootstrap/local.backend.hcl' \
  'tests/terraform/__pycache__/test_verifier.pyc' |
  git check-ignore --no-index --stdin
```

Expected: all seven paths are printed because they are ignored.

- [ ] **Step 3: Verify the dependency lock file is not ignored**

Run:

```bash
set +e
git check-ignore --no-index \
  terraform/bootstrap/.terraform.lock.hcl >/dev/null
LOCK_IGNORE_STATUS=$?
set -e

test "$LOCK_IGNORE_STATUS" -ne 0
echo "terraform_lockfile_tracking=PASS"
unset LOCK_IGNORE_STATUS
```

Expected: `terraform_lockfile_tracking=PASS`.

- [ ] **Step 4: Commit**

```bash
git add .gitignore
git diff --cached --check
git commit -m "chore: protect Terraform local artifacts"
```

### Task 3: Implement and test the AWS/Terraform preflight guard

**Files:**
- Create: `tests/terraform/test-aws-terraform-preflight.sh`
- Create: `scripts/aws-terraform-preflight.sh`

**Interfaces:**
- Consumes: profiles `agentops-lab-bootstrap` and `agentops-org-admin`.
- Produces: only `aws_terraform_preflight=PASS` on success; non-zero exit otherwise.

- [ ] **Step 1: Write the failing test**

Create `tests/terraform/test-aws-terraform-preflight.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/aws-terraform-preflight.sh"
FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN"' EXIT

cat > "$FAKE_BIN/aws" <<'FAKE_AWS'
#!/usr/bin/env bash
set -euo pipefail

if [ "${MOCK_AUTH_FAIL:-0}" = "1" ]; then
  exit 1
fi

if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
  shift 2
  profile=""
  query=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --profile) profile="$2"; shift 2 ;;
      --query) query="$2"; shift 2 ;;
      --output) shift 2 ;;
      *) shift ;;
    esac
  done

  if [ "$profile" = "agentops-lab-bootstrap" ]; then
    case "$query" in
      Account) printf '%s\n' "${MOCK_LAB_ACCOUNT:-LAB}" ;;
      Arn) printf '%s\n' "${MOCK_LAB_ARN:-arn:aws:sts::LAB:assumed-role/AgentOpsBootstrapAdmin/session}" ;;
      *) exit 2 ;;
    esac
    exit 0
  fi

  if [ "$profile" = "agentops-org-admin" ] && [ "$query" = "Account" ]; then
    printf '%s\n' "${MOCK_ORG_ACCOUNT:-ORG}"
    exit 0
  fi

  exit 2
fi

if [ "$1" = "configure" ] &&
   [ "$2" = "get" ] &&
   [ "$3" = "region" ] &&
   [ "$4" = "--profile" ] &&
   [ "$5" = "agentops-lab-bootstrap" ]; then
  printf '%s\n' "${MOCK_REGION:-us-west-2}"
  exit 0
fi

exit 2
FAKE_AWS

chmod +x "$FAKE_BIN/aws"

invoke_preflight() {
  (
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_SECURITY_TOKEN
    export PATH="$FAKE_BIN:$PATH"

    while [ "$#" -gt 0 ]; do
      export "$1"
      shift
    done

    bash "$SCRIPT"
  )
}

expect_pass() {
  name="$1"
  shift
  output="$(invoke_preflight "$@")"
  test "$output" = "aws_terraform_preflight=PASS"
  printf 'PASS: %s\n' "$name"
}

expect_fail() {
  name="$1"
  shift

  if invoke_preflight "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s unexpectedly passed\n' "$name" >&2
    exit 1
  fi

  printf 'PASS: %s\n' "$name"
}

expect_pass "valid lab identity"
expect_fail "static credential variable" "AWS_ACCESS_KEY_ID=fixture"
expect_fail "wrong role" "MOCK_LAB_ARN=arn:aws:sts::LAB:assumed-role/OrganizationAdmin/session"
expect_fail "management and lab are equal" "MOCK_ORG_ACCOUNT=LAB"
expect_fail "wrong region" "MOCK_REGION=us-east-1"
expect_fail "authentication failure" "MOCK_AUTH_FAIL=1"

echo "preflight_tests=PASS"
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
bash tests/terraform/test-aws-terraform-preflight.sh
```

Expected: FAIL because the implementation does not exist.

- [ ] **Step 3: Implement the fail-closed guard**

Create `scripts/aws-terraform-preflight.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

LAB_PROFILE="${AGENTOPS_LAB_PROFILE:-agentops-lab-bootstrap}"
ORG_PROFILE="${AGENTOPS_ORG_PROFILE:-agentops-org-admin}"
EXPECTED_REGION="${AGENTOPS_REGION:-us-west-2}"

fail() {
  printf 'aws_terraform_preflight=FAIL_%s\n' "$1" >&2
  exit 1
}

if [ -n "${AWS_ACCESS_KEY_ID:-}" ] ||
   [ -n "${AWS_SECRET_ACCESS_KEY:-}" ] ||
   [ -n "${AWS_SESSION_TOKEN:-}" ] ||
   [ -n "${AWS_SECURITY_TOKEN:-}" ]; then
  fail "STATIC_CREDENTIAL_ENVIRONMENT"
fi

command -v aws >/dev/null 2>&1 || fail "AWS_CLI_NOT_FOUND"

LAB_ACCOUNT="$(aws sts get-caller-identity \
  --profile "$LAB_PROFILE" --query Account --output text 2>/dev/null)" ||
  fail "LAB_AUTHENTICATION"

LAB_ARN="$(aws sts get-caller-identity \
  --profile "$LAB_PROFILE" --query Arn --output text 2>/dev/null)" ||
  fail "LAB_ROLE_LOOKUP"

ORG_ACCOUNT="$(aws sts get-caller-identity \
  --profile "$ORG_PROFILE" --query Account --output text 2>/dev/null)" ||
  fail "MANAGEMENT_AUTHENTICATION"

LAB_REGION="$(aws configure get region \
  --profile "$LAB_PROFILE" 2>/dev/null)" ||
  fail "REGION_LOOKUP"

[ "$LAB_ACCOUNT" != "$ORG_ACCOUNT" ] ||
  fail "LAB_EQUALS_MANAGEMENT"

case "$LAB_ARN" in
  *AgentOpsBootstrapAdmin*) ;;
  *) fail "UNEXPECTED_LAB_ROLE" ;;
esac

[ "$LAB_REGION" = "$EXPECTED_REGION" ] ||
  fail "UNEXPECTED_REGION"

unset LAB_ACCOUNT LAB_ARN ORG_ACCOUNT LAB_REGION
echo "aws_terraform_preflight=PASS"
```

- [ ] **Step 4: Run syntax, mock, and real-profile tests**

```bash
chmod +x scripts/aws-terraform-preflight.sh
chmod +x tests/terraform/test-aws-terraform-preflight.sh

bash -n scripts/aws-terraform-preflight.sh
bash -n tests/terraform/test-aws-terraform-preflight.sh
bash tests/terraform/test-aws-terraform-preflight.sh
scripts/aws-terraform-preflight.sh
```

Expected:

```text
preflight_tests=PASS
aws_terraform_preflight=PASS
```

- [ ] **Step 5: Commit**

```bash
git add scripts/aws-terraform-preflight.sh \
  tests/terraform/test-aws-terraform-preflight.sh
git diff --cached --check
git commit -m "test: guard Terraform AWS identity"
```

### Task 4: Build the local-state S3 bootstrap root with Terraform tests

**Files:**
- Create: `terraform/README.md`
- Create: `terraform/bootstrap/README.md`
- Create: `terraform/bootstrap/versions.tf`
- Create: `terraform/bootstrap/providers.tf`
- Create: `terraform/bootstrap/variables.tf`
- Create: `terraform/bootstrap/main.tf`
- Create: `terraform/bootstrap/outputs.tf`
- Create: `terraform/bootstrap/tests/bootstrap.tftest.hcl`
- Must remain absent: `terraform/bootstrap/backend.tf`

**Interfaces:**
- Consumes: `AWS_PROFILE=agentops-lab-bootstrap` and validated region.
- Produces: a root whose plan contains exactly six protected S3 resources.

- [ ] **Step 1: Write the failing Terraform contract test**

Create `terraform/bootstrap/tests/bootstrap.tftest.hcl`:

```hcl
mock_provider "aws" {}

run "protected_state_bucket_contract" {
  command = plan

  variables {
    aws_region   = "us-west-2"
    project_name = "agentops-eks"
  }

  assert {
    condition     = aws_s3_bucket.state.bucket_prefix == "agentops-eks-tfstate-"
    error_message = "The bucket must use the private generated-name prefix."
  }

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "The state bucket must reject force deletion."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State versioning must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.state.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "State encryption must use explicit SSE-S3."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets
    ])
    error_message = "All four S3 public-access blocks must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.state.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled with Bucket Owner Enforced."
  }
}

run "reject_wrong_region" {
  command = plan

  variables {
    aws_region = "us-east-1"
  }

  expect_failures = [var.aws_region]
}
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
terraform -chdir=terraform/bootstrap init -backend=false
terraform -chdir=terraform/bootstrap test
```

Expected: FAIL because configuration does not yet exist.

- [ ] **Step 3: Create version and provider configuration**

Create `terraform/bootstrap/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.61.0"
    }
  }
}
```

Create `terraform/bootstrap/providers.tf`:

```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = "bootstrap"
    ManagedBy   = "Terraform"
    Purpose     = "RemoteState"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
```

- [ ] **Step 4: Create validated inputs**

Create `terraform/bootstrap/variables.tf`:

```hcl
variable "aws_region" {
  description = "AWS region that stores the AgentOps Terraform backend."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.aws_region == "us-west-2"
    error_message = "The approved AgentOps region is us-west-2."
  }
}

variable "project_name" {
  description = "Stable lowercase project identifier used in names and tags."
  type        = string
  default     = "agentops-eks"

  validation {
    condition = (
      length(var.project_name) >= 3 &&
      length(var.project_name) <= 30 &&
      can(regex("^[a-z0-9-]+$", var.project_name))
    )
    error_message = "project_name must contain 3-30 lowercase letters, numbers, or hyphens."
  }
}
```

- [ ] **Step 5: Create the protected S3 resources**

Create `terraform/bootstrap/main.tf`:

```hcl
resource "aws_s3_bucket" "state" {
  bucket_prefix = "${var.project_name}-tfstate-"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

data "aws_iam_policy_document" "state" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*"
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state.json

  lifecycle {
    prevent_destroy = true
  }
}
```

The policy data source renders JSON locally; it is not a seventh AWS resource.

- [ ] **Step 6: Create privacy-aware outputs**

Create `terraform/bootstrap/outputs.tf`:

```hcl
output "state_bucket_name" {
  description = "Generated S3 bucket name. Keep this value private."
  value       = aws_s3_bucket.state.id
  sensitive   = true
}

output "state_bucket_region" {
  description = "Region containing the Terraform state bucket."
  value       = var.aws_region
}
```

- [ ] **Step 7: Create Terraform documentation**

Create `terraform/README.md`:

```markdown
# Terraform roots

This project uses explicit root directories instead of Terraform workspaces.

| Root | State key | Responsibility |
|---|---|---|
| bootstrap | bootstrap/terraform.tfstate | S3 backend and protection controls |
| environments/dev | environments/dev/terraform.tfstate | v0.1 resources added in later workstreams |

Always authenticate through IAM Identity Center and run `scripts/aws-terraform-preflight.sh` before Terraform.

The bootstrap root initially uses local state only long enough to create and verify S3. Its state is then migrated. Normal dev teardown never targets bootstrap.

Never commit or publish state, binary plans, backend caches, real bucket names, account identifiers, ARNs, or credentials.
```

Create `terraform/bootstrap/README.md`:

```markdown
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
```

- [ ] **Step 8: Confirm backend absence**

```bash
test ! -e terraform/bootstrap/backend.tf
echo "initial_backend_absence=PASS"
```

- [ ] **Step 9: Format, initialize locally, test, and validate**

```bash
terraform -chdir=terraform/bootstrap fmt -recursive
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap test
terraform -chdir=terraform/bootstrap validate
```

Expected: two test runs pass, validation succeeds, `.terraform.lock.hcl` is generated, and no S3 migration prompt appears.

- [ ] **Step 10: Commit**

```bash
git add terraform/README.md terraform/bootstrap
git diff --cached --check
git commit -m "feat: define protected Terraform state bucket"
```

### Task 5: Implement an automated bootstrap-plan allowlist

**Files:**
- Create: `tests/terraform/test_verify_bootstrap_plan.py`
- Create: `scripts/verify-bootstrap-plan.py`

**Interfaces:**
- Consumes: JSON from `terraform show -json`.
- Produces: `bootstrap_plan_contract=PASS` only for exactly six create-only S3 resource types.

- [ ] **Step 1: Write the failing Python test**

Create `tests/terraform/test_verify_bootstrap_plan.py`:

```python
import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "verify-bootstrap-plan.py"

ALLOWED_TYPES = [
    "aws_s3_bucket",
    "aws_s3_bucket_ownership_controls",
    "aws_s3_bucket_public_access_block",
    "aws_s3_bucket_versioning",
    "aws_s3_bucket_server_side_encryption_configuration",
    "aws_s3_bucket_policy",
]


def plan(resource_types, actions=None):
    selected_actions = actions or ["create"]
    return {
        "resource_changes": [
            {
                "address": f"{resource_type}.state",
                "mode": "managed",
                "type": resource_type,
                "change": {"actions": selected_actions},
            }
            for resource_type in resource_types
        ]
    }


def run_verifier(payload):
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    )


class BootstrapPlanVerifierTest(unittest.TestCase):
    def test_accepts_exact_create_only_contract(self):
        result = run_verifier(plan(ALLOWED_TYPES))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "bootstrap_plan_contract=PASS")

    def test_rejects_unexpected_resource(self):
        result = run_verifier(plan(ALLOWED_TYPES + ["aws_dynamodb_table"]))
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_destroy_action(self):
        result = run_verifier(plan(ALLOWED_TYPES, ["delete"]))
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_missing_resource(self):
        result = run_verifier(plan(ALLOWED_TYPES[:-1]))
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
python3 -m unittest tests/terraform/test_verify_bootstrap_plan.py -v
```

Expected: FAIL because the verifier does not exist.

- [ ] **Step 3: Implement the verifier**

Create `scripts/verify-bootstrap-plan.py`:

```python
#!/usr/bin/env python3
import json
import sys

EXPECTED_TYPES = {
    "aws_s3_bucket",
    "aws_s3_bucket_ownership_controls",
    "aws_s3_bucket_public_access_block",
    "aws_s3_bucket_versioning",
    "aws_s3_bucket_server_side_encryption_configuration",
    "aws_s3_bucket_policy",
}


def fail(reason):
    print(f"bootstrap_plan_contract=FAIL_{reason}", file=sys.stderr)
    raise SystemExit(1)


try:
    plan = json.load(sys.stdin)
except (json.JSONDecodeError, UnicodeDecodeError):
    fail("INVALID_JSON")

changes = []

for item in plan.get("resource_changes", []):
    if item.get("mode") != "managed":
        continue

    actions = item.get("change", {}).get("actions", [])
    if actions == ["no-op"]:
        continue

    changes.append((item.get("type"), actions))

actual_types = {resource_type for resource_type, _ in changes}

if len(changes) != len(EXPECTED_TYPES):
    fail("UNEXPECTED_RESOURCE_COUNT")

if actual_types != EXPECTED_TYPES:
    fail("UNEXPECTED_RESOURCE_TYPE")

if any(actions != ["create"] for _, actions in changes):
    fail("NON_CREATE_ACTION")

print("bootstrap_plan_contract=PASS")
```

- [ ] **Step 4: Run tests and commit**

```bash
chmod +x scripts/verify-bootstrap-plan.py
python3 -m unittest tests/terraform/test_verify_bootstrap_plan.py -v

git add scripts/verify-bootstrap-plan.py \
  tests/terraform/test_verify_bootstrap_plan.py
git diff --cached --check
git commit -m "test: allowlist Terraform bootstrap plan"
```

Expected: four tests pass before commit.

### Task 6: Run the complete no-cost static verification

**Files:** No new files.

**Interfaces:**
- Consumes: Tasks 1-5.
- Produces: a green static checkpoint before any real AWS plan.

- [ ] **Step 1: Run shell and Python tests**

```bash
bash -n scripts/aws-terraform-preflight.sh
bash tests/terraform/test-aws-terraform-preflight.sh
python3 -m unittest tests/terraform/test_verify_bootstrap_plan.py -v
```

- [ ] **Step 2: Run Terraform checks**

```bash
terraform fmt -check -recursive terraform
terraform -chdir=terraform/bootstrap init -backend=false
terraform -chdir=terraform/bootstrap test
terraform -chdir=terraform/bootstrap validate
```

- [ ] **Step 3: Verify initial backend and DynamoDB absence**

```bash
test ! -e terraform/bootstrap/backend.tf

set +e
FORBIDDEN_LOCKING="$(
  rg -n 'dynamodb_table|aws_dynamodb_table' \
    terraform 2>/dev/null
)"
FORBIDDEN_STATUS=$?
set -e

test "$FORBIDDEN_STATUS" -eq 1
test -z "$FORBIDDEN_LOCKING"

echo "pre_apply_static_verification=PASS"

unset FORBIDDEN_LOCKING
unset FORBIDDEN_STATUS
```

Expected: `pre_apply_static_verification=PASS`.

### Task 7: Produce and review the first real AWS plan

**Files:**
- Runtime only: `terraform/bootstrap/bootstrap.tfplan` — ignored and removed after apply.

**Interfaces:**
- Consumes: real `agentops-lab-bootstrap` SSO access.
- Produces: a saved, reviewed, create-only plan containing exactly six approved resources.

- [ ] **Step 1: Export only profile and region selectors**

```bash
export AWS_PROFILE=agentops-lab-bootstrap
export AWS_REGION=us-west-2
export AWS_DEFAULT_REGION=us-west-2
```

Do not export access keys.

- [ ] **Step 2: Run preflight immediately before planning**

```bash
scripts/aws-terraform-preflight.sh
```

Expected: `aws_terraform_preflight=PASS`.

- [ ] **Step 3: Reconfirm that the generated-name prefix is still unused**

```bash
PREPLAN_BUCKET_COUNT="$(
  aws s3api list-buckets \
    --profile agentops-lab-bootstrap \
    --query "length(Buckets[?starts_with(Name, 'agentops-eks-tfstate-')])" \
    --output text
)"

test "$PREPLAN_BUCKET_COUNT" = "0"
echo "preplan_project_bucket_inventory=PASS"
unset PREPLAN_BUCKET_COUNT
```

Expected: `preplan_project_bucket_inventory=PASS`.

This repeat closes the time gap between the initial checkpoint and the real plan. Stop if the count is not zero.

- [ ] **Step 4: Create a saved plan**

```bash
terraform -chdir=terraform/bootstrap plan \
  -out=bootstrap.tfplan
```

Expected summary: six resources to add, zero to change, zero to destroy.

Stop if the count differs or any resource is outside the approved S3 controls.

- [ ] **Step 5: Verify the machine-readable allowlist**

```bash
terraform -chdir=terraform/bootstrap show \
  -json bootstrap.tfplan |
  scripts/verify-bootstrap-plan.py
```

Expected: `bootstrap_plan_contract=PASS`.

- [ ] **Step 6: Review the human-readable plan**

```bash
terraform -chdir=terraform/bootstrap show \
  -no-color bootstrap.tfplan
```

Confirm:

- the name is generated and is not copied into Git or chat;
- `force_destroy` is false;
- versioning is Enabled;
- encryption is AES256;
- all four public-access values are true;
- ownership is BucketOwnerEnforced;
- the policy contains only the non-TLS deny;
- tags match the approved project.

- [ ] **Step 7: Stop for explicit apply approval**

Report only:

```text
preflight=PASS
preplan_project_bucket_inventory=PASS
bootstrap_plan_contract=PASS
bootstrap_plan_add=6
bootstrap_plan_change=0
bootstrap_plan_destroy=0
```

Do not apply until the human approves this exact saved plan.

### Task 8: Implement and test S3 security readback

**Files:**
- Create: `tests/terraform/test-verify-state-bucket.sh`
- Create: `scripts/verify-state-bucket.sh`

**Interfaces:**
- Consumes: `STATE_BUCKET_NAME` and temporary SSO credentials.
- Produces: `state_bucket_readback=PASS` without printing a bucket name, ARN, account, or policy.

- [ ] **Step 1: Write the failing mock test**

Create `tests/terraform/test-verify-state-bucket.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/verify-state-bucket.sh"
FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN"' EXIT

cat > "$FAKE_BIN/aws" <<'FAKE_AWS'
#!/usr/bin/env bash
set -euo pipefail

case " $* " in
  *" get-bucket-location "*) printf '%s\n' "${MOCK_REGION:-us-west-2}" ;;
  *" get-bucket-versioning "*) printf '%s\n' "${MOCK_VERSIONING:-Enabled}" ;;
  *" get-bucket-encryption "*) printf '%s\n' "${MOCK_ENCRYPTION:-AES256}" ;;
  *" get-public-access-block "*) printf '%s\n' "${MOCK_PUBLIC_BLOCK:-true}" ;;
  *" get-bucket-ownership-controls "*) printf '%s\n' "${MOCK_OWNERSHIP:-BucketOwnerEnforced}" ;;
  *" get-bucket-policy "*)
    if [ "${MOCK_TLS_POLICY:-valid}" = "valid" ]; then
      printf '%s\n' '{"Version":"2012-10-17","Statement":[{"Sid":"DenyInsecureTransport","Effect":"Deny","Action":"s3:*","Resource":["bucket","bucket/*"],"Condition":{"Bool":{"aws:SecureTransport":"false"}}}]}'
    else
      printf '%s\n' '{"Version":"2012-10-17","Statement":[]}'
    fi
    ;;
  *" get-bucket-tagging "*) printf '%s\n' "${MOCK_TAG_COUNT:-1}" ;;
  *) exit 2 ;;
esac
FAKE_AWS

chmod +x "$FAKE_BIN/aws"

invoke_readback() {
  (
    export PATH="$FAKE_BIN:$PATH"
    export STATE_BUCKET_NAME="agentops-eks-tfstate-fixture"

    while [ "$#" -gt 0 ]; do
      export "$1"
      shift
    done

    bash "$SCRIPT"
  )
}

expect_pass() {
  output="$(invoke_readback)"
  test "$output" = "state_bucket_readback=PASS"
  echo "PASS: valid bucket controls"
}

expect_fail() {
  name="$1"
  shift

  if invoke_readback "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s unexpectedly passed\n' "$name" >&2
    exit 1
  fi

  printf 'PASS: %s\n' "$name"
}

expect_pass
expect_fail "wrong region" "MOCK_REGION=us-east-1"
expect_fail "versioning disabled" "MOCK_VERSIONING=Suspended"
expect_fail "wrong encryption" "MOCK_ENCRYPTION=aws:kms"
expect_fail "public access not blocked" "MOCK_PUBLIC_BLOCK=false"
expect_fail "ACL ownership enabled" "MOCK_OWNERSHIP=ObjectWriter"
expect_fail "missing TLS deny" "MOCK_TLS_POLICY=invalid"
expect_fail "missing tags" "MOCK_TAG_COUNT=0"

echo "state_bucket_readback_tests=PASS"
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
bash tests/terraform/test-verify-state-bucket.sh
```

Expected: FAIL because the implementation does not exist.

- [ ] **Step 3: Implement the readback script**

Create `scripts/verify-state-bucket.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AGENTOPS_LAB_PROFILE:-agentops-lab-bootstrap}"
EXPECTED_REGION="${AGENTOPS_REGION:-us-west-2}"
BUCKET="${STATE_BUCKET_NAME:-}"

fail() {
  printf 'state_bucket_readback=FAIL_%s\n' "$1" >&2
  exit 1
}

case "$BUCKET" in
  agentops-eks-tfstate-*) ;;
  *) fail "UNEXPECTED_BUCKET_NAME" ;;
esac

REGION="$(aws s3api get-bucket-location \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query LocationConstraint --output text 2>/dev/null)" ||
  fail "REGION_READ"

[ "$REGION" = "$EXPECTED_REGION" ] || fail "REGION"

VERSIONING="$(aws s3api get-bucket-versioning \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query Status --output text 2>/dev/null)" ||
  fail "VERSIONING_READ"

[ "$VERSIONING" = "Enabled" ] || fail "VERSIONING"

ENCRYPTION="$(aws s3api get-bucket-encryption \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
  --output text 2>/dev/null)" ||
  fail "ENCRYPTION_READ"

[ "$ENCRYPTION" = "AES256" ] || fail "ENCRYPTION"

for setting in \
  BlockPublicAcls \
  BlockPublicPolicy \
  IgnorePublicAcls \
  RestrictPublicBuckets
do
  value="$(aws s3api get-public-access-block \
    --bucket "$BUCKET" --profile "$PROFILE" \
    --query "PublicAccessBlockConfiguration.$setting" \
    --output text 2>/dev/null)" ||
    fail "PUBLIC_ACCESS_READ"

  case "$value" in
    true|True) ;;
    *) fail "PUBLIC_ACCESS" ;;
  esac
done

OWNERSHIP="$(aws s3api get-bucket-ownership-controls \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query 'OwnershipControls.Rules[0].ObjectOwnership' \
  --output text 2>/dev/null)" ||
  fail "OWNERSHIP_READ"

[ "$OWNERSHIP" = "BucketOwnerEnforced" ] || fail "OWNERSHIP"

POLICY="$(aws s3api get-bucket-policy \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query Policy --output text 2>/dev/null)" ||
  fail "POLICY_READ"

if ! printf '%s' "$POLICY" | python3 -c '
import json
import sys

policy = json.load(sys.stdin)
valid = any(
    statement.get("Effect") == "Deny"
    and statement.get("Condition", {})
        .get("Bool", {})
        .get("aws:SecureTransport") == "false"
    for statement in policy.get("Statement", [])
)
raise SystemExit(0 if valid else 1)
'; then
  fail "TLS_POLICY"
fi

for pair in \
  "Project=agentops-eks" \
  "Environment=bootstrap" \
  "ManagedBy=Terraform" \
  "Purpose=RemoteState"
do
  key="${pair%%=*}"
  expected="${pair#*=}"

  count="$(aws s3api get-bucket-tagging \
    --bucket "$BUCKET" --profile "$PROFILE" \
    --query "length(TagSet[?Key=='$key' && Value=='$expected'])" \
    --output text 2>/dev/null)" ||
    fail "TAG_READ"

  [ "$count" = "1" ] || fail "TAG"
done

unset REGION VERSIONING ENCRYPTION OWNERSHIP POLICY
unset value pair key expected count
echo "state_bucket_readback=PASS"
```

- [ ] **Step 4: Run syntax and mock verification**

```bash
chmod +x scripts/verify-state-bucket.sh
chmod +x tests/terraform/test-verify-state-bucket.sh

bash -n scripts/verify-state-bucket.sh
bash -n tests/terraform/test-verify-state-bucket.sh
bash tests/terraform/test-verify-state-bucket.sh
```

Expected: `state_bucket_readback_tests=PASS`.

- [ ] **Step 5: Commit before applying**

```bash
git add scripts/verify-state-bucket.sh \
  tests/terraform/test-verify-state-bucket.sh
git diff --cached --check
git commit -m "test: verify Terraform state bucket controls"
```

### Task 9: Apply, read back S3, and migrate bootstrap state

**Files:**
- Create after readback: `terraform/bootstrap/backend.tf`

**Interfaces:**
- Consumes: the exact approved `bootstrap.tfplan`.
- Produces: protected S3 plus remote `bootstrap/terraform.tfstate`.

- [ ] **Step 1: Re-run preflight and saved-plan verification**

```bash
scripts/aws-terraform-preflight.sh

terraform -chdir=terraform/bootstrap show \
  -json bootstrap.tfplan |
  scripts/verify-bootstrap-plan.py
```

Expected:

```text
aws_terraform_preflight=PASS
bootstrap_plan_contract=PASS
```

- [ ] **Step 2: Apply only the approved saved plan**

```bash
terraform -chdir=terraform/bootstrap apply bootstrap.tfplan
```

Expected: six resources created.

Stop on partial failure. Do not regenerate and auto-apply another plan.

Terraform's apply progress can display the generated bucket name as a resource ID. Do not paste raw apply output into chat, issues, pull requests, or public evidence; record only the sanitized PASS/FAIL results from the verification steps.

- [ ] **Step 3: Resolve the private bucket name without printing it**

```bash
STATE_BUCKET_NAME="$(
  terraform -chdir=terraform/bootstrap \
    output -raw state_bucket_name
)"
test -n "$STATE_BUCKET_NAME"
export STATE_BUCKET_NAME

case "$STATE_BUCKET_NAME" in
  agentops-eks-tfstate-*) ;;
  *) exit 1 ;;
esac

MATCHING_BUCKET_COUNT="$(
  aws s3api list-buckets \
    --profile agentops-lab-bootstrap \
    --query "length(Buckets[?starts_with(Name, 'agentops-eks-tfstate-')])" \
    --output text
)"
test "$MATCHING_BUCKET_COUNT" = "1"

MATCHING_BUCKET="$(
  aws s3api list-buckets \
    --profile agentops-lab-bootstrap \
    --query "Buckets[?starts_with(Name, 'agentops-eks-tfstate-')].Name | [0]" \
    --output text
)"
test "$MATCHING_BUCKET" = "$STATE_BUCKET_NAME"

echo "state_bucket_resolution=PASS"
echo "post_apply_bucket_inventory=PASS"

unset MATCHING_BUCKET MATCHING_BUCKET_COUNT
```

Do not run `echo "$STATE_BUCKET_NAME"`. Stop if the active account owns zero or more than one bucket matching the prefix, or if the sole match differs from the Terraform output.

- [ ] **Step 4: Read back every AWS control**

```bash
scripts/verify-state-bucket.sh
```

Expected: `state_bucket_readback=PASS`.

Do not add `backend.tf` if readback fails.

- [ ] **Step 5: Add the partial bootstrap backend**

Create `terraform/bootstrap/backend.tf`:

```hcl
terraform {
  backend "s3" {
    key          = "bootstrap/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

- [ ] **Step 6: Migrate local bootstrap state**

```bash
terraform -chdir=terraform/bootstrap fmt -check

terraform -chdir=terraform/bootstrap init \
  -migrate-state \
  -backend-config="bucket=$STATE_BUCKET_NAME"
```

Confirm copying state only when the source is the bootstrap state just applied and the destination key is `bootstrap/terraform.tfstate`. Stop on any other bucket, key, state, or workspace.

- [ ] **Step 7: Prove remote state exists without displaying it**

```bash
terraform -chdir=terraform/bootstrap state pull >/dev/null

aws s3api head-object \
  --bucket "$STATE_BUCKET_NAME" \
  --key bootstrap/terraform.tfstate \
  --profile agentops-lab-bootstrap \
  >/dev/null

echo "bootstrap_remote_state=PASS"
```

- [ ] **Step 8: Prove ordinary bootstrap destroy is blocked**

```bash
set +e
DESTROY_OUTPUT="$(
  terraform -chdir=terraform/bootstrap plan \
    -destroy -lock-timeout=10s -no-color 2>&1
)"
DESTROY_STATUS=$?
set -e

test "$DESTROY_STATUS" -ne 0

case "$DESTROY_OUTPUT" in
  *"Instance cannot be destroyed"*)
    echo "bootstrap_destroy_guard=PASS"
    ;;
  *)
    echo "bootstrap_destroy_guard=INCONCLUSIVE"
    exit 1
    ;;
esac

unset DESTROY_OUTPUT DESTROY_STATUS
```

This negative test plans only; it must never apply.

- [ ] **Step 9: Remove the consumed plan and commit the backend**

```bash
test -f terraform/bootstrap/bootstrap.tfplan
rm -f terraform/bootstrap/bootstrap.tfplan
test ! -e terraform/bootstrap/bootstrap.tfplan

git add terraform/bootstrap/backend.tf
git diff --cached --check
git commit -m "feat: migrate bootstrap state to S3"
```

Do not add local state or `.terraform/`.

### Task 10: Create and verify the separate dev backend contract

**Files:**
- Create: `terraform/environments/dev/README.md`
- Create: `terraform/environments/dev/versions.tf`
- Create: `terraform/environments/dev/backend.tf`
- Create: `terraform/environments/dev/main.tf`
- Create: `terraform/environments/dev/outputs.tf`
- Create: `terraform/environments/dev/tests/backend_contract.tftest.hcl`

**Interfaces:**
- Consumes: the resolved S3 bucket.
- Produces: `environments/dev/terraform.tfstate` with one cost-free contract.

- [ ] **Step 1: Write the contract test**

Create `terraform/environments/dev/tests/backend_contract.tftest.hcl`:

```hcl
run "backend_contract" {
  command = plan

  assert {
    condition     = terraform_data.backend_contract.input.project == "agentops-eks"
    error_message = "The contract must identify agentops-eks."
  }

  assert {
    condition     = terraform_data.backend_contract.input.environment == "dev"
    error_message = "The contract must identify dev."
  }

  assert {
    condition     = terraform_data.backend_contract.input.backend == "s3"
    error_message = "The contract must identify S3."
  }

  assert {
    condition     = terraform_data.backend_contract.input.locking == "native-s3-lockfile"
    error_message = "The contract must identify native S3 locking."
  }
}
```

- [ ] **Step 2: Create version and backend files**

Create `terraform/environments/dev/versions.tf`:

```hcl
terraform {
  required_version = ">= 1.10.0, < 2.0.0"
}
```

Create `terraform/environments/dev/backend.tf`:

```hcl
terraform {
  backend "s3" {
    key          = "environments/dev/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
```

- [ ] **Step 3: Create the cost-free state contract**

Create `terraform/environments/dev/main.tf`:

```hcl
resource "terraform_data" "backend_contract" {
  input = {
    project     = "agentops-eks"
    environment = "dev"
    backend     = "s3"
    locking     = "native-s3-lockfile"
  }
}
```

Create `terraform/environments/dev/outputs.tf`:

```hcl
output "backend_contract" {
  description = "Non-sensitive proof that dev uses the approved backend contract."
  value       = terraform_data.backend_contract.output
}
```

`terraform_data` is built into Terraform. It writes state but creates no AWS resource and has no cloud cost.

- [ ] **Step 4: Document dev initialization**

Create `terraform/environments/dev/README.md`:

```markdown
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
```

- [ ] **Step 5: Format and run no-backend tests**

```bash
terraform -chdir=terraform/environments/dev fmt -recursive
terraform -chdir=terraform/environments/dev init -backend=false
terraform -chdir=terraform/environments/dev test
terraform -chdir=terraform/environments/dev validate
```

- [ ] **Step 6: Initialize the real dev backend**

```bash
scripts/aws-terraform-preflight.sh

if [ -z "${STATE_BUCKET_NAME:-}" ]; then
  STATE_BUCKET_NAME="$(
    terraform -chdir=terraform/bootstrap output -raw state_bucket_name
  )"
  test -n "$STATE_BUCKET_NAME"
  export STATE_BUCKET_NAME
fi

terraform -chdir=terraform/environments/dev init \
  -backend-config="bucket=$STATE_BUCKET_NAME"
```

- [ ] **Step 7: Create and automatically verify the dev plan**

```bash
terraform -chdir=terraform/environments/dev plan \
  -out=dev-backend.tfplan

terraform -chdir=terraform/environments/dev show \
  -json dev-backend.tfplan |
python3 -c '
import json
import sys

plan = json.load(sys.stdin)
changes = [
    change
    for change in plan.get("resource_changes", [])
    if change.get("change", {}).get("actions") != ["no-op"]
]

valid = (
    len(changes) == 1
    and changes[0].get("address") == "terraform_data.backend_contract"
    and changes[0].get("type") == "terraform_data"
    and changes[0].get("change", {}).get("actions") == ["create"]
)

if not valid:
    raise SystemExit("dev_plan_contract=FAIL")

print("dev_plan_contract=PASS")
'

terraform -chdir=terraform/environments/dev show \
  -no-color dev-backend.tfplan
```

Expected: `dev_plan_contract=PASS`, followed by a human-readable plan containing exactly one `terraform_data.backend_contract` to add and no `aws_*` resource.

- [ ] **Step 8: Stop for explicit dev-contract apply approval**

Report only:

```text
dev_plan_contract=PASS
dev_plan_add=1
dev_plan_change=0
dev_plan_destroy=0
```

Do not apply until the human approves this exact saved plan. Although `terraform_data` has no AWS cost, it still mutates the remote `dev` state and therefore uses the same reviewed-plan discipline.

- [ ] **Step 9: Apply the approved cost-free contract**

```bash
terraform -chdir=terraform/environments/dev apply dev-backend.tfplan
```

- [ ] **Step 10: Verify remote dev state without printing it**

```bash
REMOTE_STATE_FILE="$(mktemp)"
trap 'rm -f "$REMOTE_STATE_FILE"' EXIT

terraform -chdir=terraform/environments/dev \
  state pull > "$REMOTE_STATE_FILE"

python3 - "$REMOTE_STATE_FILE" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as state_file:
    state = json.load(state_file)

resources = state.get("resources", [])
valid = (
    len(resources) == 1
    and resources[0].get("mode") == "managed"
    and resources[0].get("type") == "terraform_data"
    and resources[0].get("name") == "backend_contract"
)

if not valid:
    raise SystemExit("dev_remote_state_contract=FAIL")

print("dev_remote_state_contract=PASS")
PY

aws s3api head-object \
  --bucket "$STATE_BUCKET_NAME" \
  --key environments/dev/terraform.tfstate \
  --profile agentops-lab-bootstrap \
  >/dev/null

echo "dev_remote_state_object=PASS"
```

- [ ] **Step 11: Prove routine dev teardown cannot include the state bucket**

Create a destroy plan for inspection only:

```bash
terraform -chdir=terraform/environments/dev plan \
  -destroy \
  -out=dev-destroy-check.tfplan

terraform -chdir=terraform/environments/dev show \
  -json dev-destroy-check.tfplan |
python3 -c '
import json
import sys

plan = json.load(sys.stdin)
changes = [
    change
    for change in plan.get("resource_changes", [])
    if change.get("change", {}).get("actions") != ["no-op"]
]

valid = (
    len(changes) == 1
    and changes[0].get("address") == "terraform_data.backend_contract"
    and changes[0].get("type") == "terraform_data"
    and changes[0].get("change", {}).get("actions") == ["delete"]
)

if not valid:
    raise SystemExit("dev_teardown_isolation=FAIL")

print("dev_teardown_isolation=PASS")
'

rm -f terraform/environments/dev/dev-destroy-check.tfplan
```

This command never applies the destroy plan. Exact-one validation proves that routine dev teardown sees only the cost-free contract; the S3 bucket is owned by the separate bootstrap root and is absent from the dev dependency graph.

- [ ] **Step 12: Remove runtime files and commit**

```bash
rm -f terraform/environments/dev/dev-backend.tfplan
rm -f "$REMOTE_STATE_FILE"
trap - EXIT
unset REMOTE_STATE_FILE

git add terraform/environments/dev
git diff --cached --check
git commit -m "feat: verify Terraform dev remote state"
```

### Task 11: Verify drift, locking configuration, and repository privacy

**Files:** No new files.

**Interfaces:**
- Consumes: both remote backends.
- Produces: final PASS results without raw state or identifiers.

- [ ] **Step 1: Verify both roots have no drift**

```bash
set +e

terraform -chdir=terraform/bootstrap plan \
  -detailed-exitcode -lock-timeout=10s -no-color >/dev/null
BOOTSTRAP_DRIFT_STATUS=$?

terraform -chdir=terraform/environments/dev plan \
  -detailed-exitcode -lock-timeout=10s -no-color >/dev/null
DEV_DRIFT_STATUS=$?

set -e

test "$BOOTSTRAP_DRIFT_STATUS" -eq 0
test "$DEV_DRIFT_STATUS" -eq 0
echo "terraform_drift_check=PASS"

unset BOOTSTRAP_DRIFT_STATUS DEV_DRIFT_STATUS
```

Exit code 0 means no changes. Exit code 2 means drift and cannot be counted as PASS. Exit code 1 is an error.

- [ ] **Step 2: Verify native S3 locking is configured twice**

```bash
LOCKFILE_CONFIG_COUNT="$(
  rg -n 'use_lockfile[[:space:]]*=[[:space:]]*true' \
    terraform/bootstrap/backend.tf \
    terraform/environments/dev/backend.tf |
  wc -l |
  tr -d ' '
)"

test "$LOCKFILE_CONFIG_COUNT" = "2"
echo "native_s3_lockfile_config=PASS"
unset LOCKFILE_CONFIG_COUNT
```

- [ ] **Step 3: Verify DynamoDB locking is absent**

```bash
set +e
DYNAMODB_MATCHES="$(
  rg -n 'dynamodb_table|aws_dynamodb_table' \
    terraform 2>/dev/null
)"
DYNAMODB_STATUS=$?
set -e

test "$DYNAMODB_STATUS" -eq 1
test -z "$DYNAMODB_MATCHES"
echo "dynamodb_locking_absence=PASS"

unset DYNAMODB_MATCHES DYNAMODB_STATUS
```

- [ ] **Step 4: Verify the actual bucket name is absent from Git**

```bash
test -n "${STATE_BUCKET_NAME:-}"

set +e
BUCKET_GIT_MATCHES="$(git grep -F "$STATE_BUCKET_NAME")"
BUCKET_GIT_STATUS=$?
set -e

test "$BUCKET_GIT_STATUS" -eq 1
test -z "$BUCKET_GIT_MATCHES"
echo "bucket_name_privacy=PASS"

unset BUCKET_GIT_MATCHES BUCKET_GIT_STATUS
```

- [ ] **Step 5: Scan for sensitive values**

```bash
set +e
PRIVACY_MATCHES="$(
  git grep -n -I \
    -e '[0-9]\{12\}' \
    -e 'https://[^ ]*awsapps\.com' \
    -e 'AKIA[0-9A-Z]\{16\}' \
    -e 'ASIA[0-9A-Z]\{16\}' \
    -e 'BEGIN \(RSA \|EC \|OPENSSH \)\?PRIVATE KEY' \
    -e 'o-[a-z0-9]\{10,32\}' \
    -e '[A-Z0-9._%+-]\+@[A-Z0-9.-]\+\.[A-Z]\{2,\}' \
    -- . 2>/dev/null
)"
PRIVACY_STATUS=$?
set -e

test "$PRIVACY_STATUS" -eq 1
test -z "$PRIVACY_MATCHES"
echo "repository_privacy_scan=PASS"

unset PRIVACY_MATCHES PRIVACY_STATUS
```

- [ ] **Step 6: Verify no runtime artifact is tracked**

```bash
set +e
RUNTIME_TRACKED="$(
  git ls-files |
  rg '(^|/)\.terraform/|\.tfstate($|\.)|\.tfplan$|\.backend\.hcl$'
)"
RUNTIME_STATUS=$?
set -e

test "$RUNTIME_STATUS" -eq 1
test -z "$RUNTIME_TRACKED"
echo "terraform_runtime_tracking=PASS"

unset RUNTIME_TRACKED RUNTIME_STATUS
```

### Task 12: Capture sanitized evidence and close the workstream

**Files:**
- Create: `docs/evidence/v0.1/terraform-state-bootstrap.md`

**Interfaces:**
- Consumes: all Task 1-11 PASS results.
- Produces: public evidence and a clean handoff to VPC/networking design.

- [ ] **Step 1: Confirm the final result matrix**

Continue only when all are PASS:

```text
terraform_version_check=PASS
tool_identity_checkpoint=PASS
initial_project_bucket_inventory=PASS
aws_terraform_preflight=PASS
pre_apply_static_verification=PASS
preplan_project_bucket_inventory=PASS
bootstrap_plan_contract=PASS
state_bucket_resolution=PASS
post_apply_bucket_inventory=PASS
state_bucket_readback=PASS
bootstrap_remote_state=PASS
bootstrap_destroy_guard=PASS
dev_plan_contract=PASS
dev_remote_state_contract=PASS
dev_remote_state_object=PASS
dev_teardown_isolation=PASS
terraform_drift_check=PASS
native_s3_lockfile_config=PASS
dynamodb_locking_absence=PASS
bucket_name_privacy=PASS
repository_privacy_scan=PASS
terraform_runtime_tracking=PASS
```

Do not infer a missing result from another test.

- [ ] **Step 2: Create evidence**

Create `docs/evidence/v0.1/terraform-state-bootstrap.md`:

```markdown
# Terraform State Bootstrap Evidence

**Completed:** 2026-08-25
**Region:** us-west-2

## Verified controls

- [x] Terraform executed only through the intended agentops-lab bootstrap role.
- [x] The management account was rejected as a Terraform target.
- [x] The S3 state bucket was created from Terraform rather than the AWS console.
- [x] The generated bucket name does not encode the AWS account ID.
- [x] S3 versioning is enabled.
- [x] Explicit SSE-S3 default encryption is enabled.
- [x] All four S3 public-access blocks are enabled.
- [x] ACLs are disabled with Bucket Owner Enforced.
- [x] The bucket policy denies non-TLS transport.
- [x] Force deletion is disabled and lifecycle guards block ordinary destruction.
- [x] Bootstrap state was migrated from temporary local state to S3.
- [x] Bootstrap and dev use separate remote-state keys.
- [x] Routine dev teardown is isolated from the bootstrap state bucket.
- [x] Native S3 lockfiles are enabled for both backends.
- [x] DynamoDB locking is not used.
- [x] A cost-free Terraform data contract proves dev can persist and retrieve state.
- [x] Final Terraform plans report no drift.
- [x] No state, plan, cache, bucket name, account identifier, or credential is tracked.

## Cost boundary

This workstream creates one small S3 bucket and no EKS, EC2, NAT gateway, load balancer, KMS key, DynamoDB table, or application resource.

## Credential model

Human execution uses temporary AWS IAM Identity Center credentials. No long-lived AWS access keys are used.

## Privacy

Account IDs, bucket names, ARNs, emails, portal URLs, state contents, tokens, credentials, and local personal paths are intentionally excluded.
```

- [ ] **Step 3: Scan evidence**

```bash
set +e
EVIDENCE_MATCHES="$(
  rg -n \
    -e '[0-9]{12}' \
    -e 'https://[^ ]*awsapps\.com' \
    -e 'AKIA[0-9A-Z]{16}' \
    -e 'ASIA[0-9A-Z]{16}' \
    -e 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' \
    -e 'o-[a-z0-9]{10,32}' \
    -e '[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}' \
    docs/evidence/v0.1/terraform-state-bootstrap.md
)"
EVIDENCE_STATUS=$?
set -e

test "$EVIDENCE_STATUS" -eq 1
test -z "$EVIDENCE_MATCHES"
echo "evidence_privacy_scan=PASS"

unset EVIDENCE_MATCHES EVIDENCE_STATUS
```

- [ ] **Step 4: Review and commit evidence**

```bash
git status --short
git diff --check
git diff -- docs/evidence/v0.1/terraform-state-bootstrap.md

git add docs/evidence/v0.1/terraform-state-bootstrap.md
git diff --cached --check
git commit -m "docs: record Terraform state bootstrap evidence"
```

- [ ] **Step 5: Run final read-only verification**

```bash
aws sso login --profile agentops-lab-bootstrap
aws sso login --profile agentops-org-admin

export AWS_PROFILE=agentops-lab-bootstrap
export AWS_REGION=us-west-2
export AWS_DEFAULT_REGION=us-west-2

scripts/aws-terraform-preflight.sh

STATE_BUCKET_NAME="$(
  terraform -chdir=terraform/bootstrap output -raw state_bucket_name
)"
test -n "$STATE_BUCKET_NAME"
export STATE_BUCKET_NAME

scripts/verify-state-bucket.sh
terraform -chdir=terraform/bootstrap state pull >/dev/null
terraform -chdir=terraform/environments/dev state pull >/dev/null
git status --short
```

Expected: both scripts PASS, both states are readable, and Git is clean.

- [ ] **Step 6: Remove private local state remnants only after remote verification**

Inspect exact ignored remnants:

```bash
find terraform/bootstrap \
  -maxdepth 1 \
  -type f \
  \( -name 'terraform.tfstate' -o -name 'terraform.tfstate.backup' \) \
  -print
```

After both remote pulls succeed, remove only:

```bash
rm -f terraform/bootstrap/terraform.tfstate
rm -f terraform/bootstrap/terraform.tfstate.backup
```

Do not delete `.terraform/` during active work; it contains local initialization metadata and provider caches, not authoritative state.

- [ ] **Step 7: Clear private shell values and SSO cache**

```bash
unset STATE_BUCKET_NAME
unset AWS_PROFILE
unset AWS_REGION
unset AWS_DEFAULT_REGION
aws sso logout
```

- [ ] **Step 8: Declare the boundary**

This bootstrap is complete only when every checkbox is complete and Task 12 evidence is committed.

Do not begin VPC/networking in the same change. The next design boundary is the cost-aware two-AZ VPC with private worker subnets and an explicitly documented single-NAT lab tradeoff.
