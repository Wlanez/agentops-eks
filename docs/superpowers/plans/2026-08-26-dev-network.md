# Dev Network Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provision and verify a two-AZ, cost-aware private EKS network foundation in the existing `dev` Terraform root.

**Architecture:** Direct AWS provider resources create a `10.20.0.0/16` VPC, two public `/20` subnets, two private `/19` subnets, one NAT Gateway, explicit route tables, an S3 Gateway endpoint, and a future EKS security group. The existing `dev` S3 backend remains the only state location; a create-only plan verifier and readback script prevent scope expansion and prove the real network before the next EKS workstream.

**Tech Stack:** Terraform `>= 1.10.0, < 2.0.0`, HashiCorp AWS Provider `~> 6.61.0`, AWS CLI v2 with IAM Identity Center, Bash, Python 3, Amazon VPC.

**Spec:** `docs/superpowers/specs/2026-08-26-dev-network-design.md`

## Global Constraints

- Target account is only `agentops-lab` through `agentops-lab-bootstrap`; region is only `us-west-2`.
- The existing `terraform/environments/dev` S3 backend key and `use_lockfile = true` remain unchanged.
- VPC CIDR is `10.20.0.0/16`; select exactly two available, opted-in AZs dynamically.
- Create two public `/20` subnets and two private `/19` subnets. Private subnets never map public IPv4 addresses on launch.
- Create exactly one NAT Gateway and one Elastic IP in the first public subnet. Document it as a non-HA cost tradeoff.
- Create only an S3 Gateway endpoint; do not create DynamoDB, ECR, STS, EC2, or other Interface endpoints.
- Do not create EKS, EC2, ECR, load balancers, ingress, VPN, bastion, or application resources in this workstream.
- No inbound SSH rule is permitted. The future EKS administrative CIDR variable must reject an empty list.
- Do not print or commit account IDs, ARNs, resource IDs, EIPs, bucket names, state, plans, credentials, SSO URLs, or personal paths.
- Every AWS change uses a saved reviewed plan. Stop after a failed preflight, plan contract, readback, or privacy scan.
- `terraform destroy` is a separately approved, scoped lab teardown. It destroys only `dev` resources, never the bootstrap state bucket.

---

## File Structure

| File | Responsibility |
|---|---|
| `terraform/environments/dev/versions.tf` | Add the AWS provider dependency while retaining the Terraform version floor. |
| `terraform/environments/dev/providers.tf` | Configure AWS region and common project/environment tags without credentials. |
| `terraform/environments/dev/variables.tf` | Define and validate VPC, AZ, administrative CIDR, project and environment inputs. |
| `terraform/environments/dev/network.tf` | Own the VPC, subnets, routes, NAT, S3 endpoint and security group. |
| `terraform/environments/dev/outputs.tf` | Retain the backend contract and add non-sensitive logical network outputs only. |
| `terraform/environments/dev/test/network.tftest.hcl` | Mock-provider contract for topology and security invariants. |
| `scripts/verify-dev-network-plan.py` | Reject plans that are not the exact approved create-only network graph. |
| `tests/terraform/test_verify_dev_network_plan.py` | Unit-test plan-verifier acceptance and rejection paths. |
| `scripts/verify-dev-network.sh` | Sanitize live AWS readback of topology, routing, tags and no-SSH invariant. |
| `tests/terraform/test-verify-dev-network.sh` | Mock AWS CLI test for the live readback guard. |
| `terraform/environments/dev/README.md` | Safe init, plan, apply, verification and teardown instructions. |
| `docs/evidence/v0.1/dev-network.md` | Sanitized plan/apply/readback and cost-boundary evidence. |

---

### Task 1: Establish the network Terraform contract and provider boundary

**Files:**
- Create: `terraform/environments/dev/providers.tf`
- Create: `terraform/environments/dev/variables.tf`
- Create: `terraform/environments/dev/test/network.tftest.hcl`
- Modify: `terraform/environments/dev/versions.tf`
- Modify: `terraform/environments/dev/outputs.tf`

**Interfaces:**
- Consumes: existing `terraform_data.backend_contract`, `backend.tf`, and remote `dev` state.
- Produces: validated variables `vpc_cidr`, `availability_zone_count`, `admin_cidr_blocks`, `project_name`, `environment`; provider default tags; tests that the later network resource names must satisfy.

- [ ] **Step 1: Add a failing topology test before AWS resources exist**

Create `terraform/environments/dev/test/network.tftest.hcl`:

```hcl
mock_provider "aws" {}

variables {
  admin_cidr_blocks = ["203.0.113.0/24"]
}

run "two_az_private_eks_network_contract" {
  command = plan

  assert {
    condition     = aws_vpc.dev.cidr_block == "10.20.0.0/16"
    error_message = "The dev VPC must use the approved /16 CIDR."
  }

  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "The network must create public and private subnets in exactly two AZs."
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.private : subnet.map_public_ip_on_launch == false])
    error_message = "Private subnets must not assign public IPv4 addresses."
  }

  assert {
    condition     = length(aws_nat_gateway.lab) == 1
    error_message = "The lab topology must create exactly one NAT Gateway."
  }

  assert {
    condition     = aws_vpc_endpoint.s3.service_name == "com.amazonaws.us-west-2.s3"
    error_message = "The only endpoint in this workstream must be the regional S3 Gateway endpoint."
  }

  assert {
    condition     = length(aws_security_group.eks_future.ingress) == 0
    error_message = "The future EKS security group must not allow inbound SSH or other inbound traffic."
  }
}
```

- [ ] **Step 2: Run the test to verify it fails because the network resources are absent**

Run:

```bash
terraform -chdir=terraform/environments/dev init -backend=false
terraform -chdir=terraform/environments/dev test
```

Expected: `backend_contract` passes and `network.tftest.hcl` fails with undeclared `aws_*` resource references.

- [ ] **Step 3: Add the provider constraint and provider configuration**

Extend `versions.tf` without changing its Terraform constraint:

```hcl
required_providers {
  aws = {
    source  = "hashicorp/aws"
    version = "~> 6.61.0"
  }
}
```

Create `providers.tf`:

```hcl
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
    Purpose     = "EKSFoundation"
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}
```

- [ ] **Step 4: Define validated inputs and safe outputs**

Create `variables.tf` with these exact defaults and validations:

```hcl
variable "aws_region" {
  type    = string
  default = "us-west-2"
  validation {
    condition     = var.aws_region == "us-west-2"
    error_message = "The approved AgentOps region is us-west-2."
  }
}

variable "project_name" { type = string, default = "agentops-eks" }
variable "environment" { type = string, default = "dev" }

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
  validation {
    condition     = var.vpc_cidr == "10.20.0.0/16"
    error_message = "The approved dev VPC CIDR is 10.20.0.0/16."
  }
}

variable "availability_zone_count" {
  type    = number
  default = 2
  validation {
    condition     = var.availability_zone_count == 2
    error_message = "The v0.1 network requires exactly two Availability Zones."
  }
}

variable "admin_cidr_blocks" {
  type      = set(string)
  sensitive = true
  validation {
    condition     = length(var.admin_cidr_blocks) > 0 && alltrue([for cidr in var.admin_cidr_blocks : can(cidrhost(cidr, 0))])
    error_message = "admin_cidr_blocks must contain at least one valid CIDR."
  }
}
```

Leave `admin_cidr_blocks` without a default. It is not consumed by a network ingress rule yet; its validation establishes the required interface for the future restricted public EKS API.

Do not add a network output yet: it must not refer to data sources or resources that Task 2 has not created.

- [ ] **Step 5: Format and run the test again**

Run:

```bash
terraform -chdir=terraform/environments/dev fmt -recursive
terraform -chdir=terraform/environments/dev test
```

Expected: the provider and variable syntax is valid; the network test still fails only because network resources are not yet implemented.

- [ ] **Step 6: Commit the contract boundary**

```bash
git add terraform/environments/dev/versions.tf terraform/environments/dev/providers.tf terraform/environments/dev/variables.tf terraform/environments/dev/outputs.tf terraform/environments/dev/test/network.tftest.hcl
git diff --cached --check
git commit -m "test: define dev network contract"
```

### Task 2: Implement the direct two-AZ network topology

**Files:**
- Create: `terraform/environments/dev/network.tf`
- Modify: `terraform/environments/dev/test/network.tftest.hcl`

**Interfaces:**
- Consumes: Task 1 variables and `local.common_tags`.
- Produces: `aws_vpc.dev`, `aws_subnet.public`, `aws_subnet.private`, `aws_internet_gateway.dev`, `aws_nat_gateway.lab`, route tables, S3 endpoint and `aws_security_group.eks_future`.

- [ ] **Step 1: Add a second failing test for explicit routing and subnet tags**

Append to `network.tftest.hcl`:

```hcl
run "routing_and_eks_discovery_contract" {
  command = plan

  assert {
    condition     = length(aws_route.private_default) == 2 && alltrue([for route in aws_route.private_default : route.nat_gateway_id == aws_nat_gateway.lab[0].id])
    error_message = "Every private subnet route table must use the single lab NAT Gateway."
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.public : subnet.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Public subnets must carry the future public load-balancer discovery tag."
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.private : subnet.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "Private subnets must carry the future internal load-balancer discovery tag."
  }
}
```

- [ ] **Step 2: Run the added test and verify it fails from missing route resources**

Run:

```bash
terraform -chdir=terraform/environments/dev test
```

Expected: the new run fails with undeclared route references.

- [ ] **Step 3: Implement `network.tf` with deterministic AZ and CIDR allocation**

Create `network.tf` with this resource shape. Keep all resource names and collection keys exactly as shown because tests and verifier depend on them.

```hcl
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  selected_azs = slice(sort(data.aws_availability_zones.available.names), 0, var.availability_zone_count)
  az_indices   = { for index, az in local.selected_azs : tostring(index) => az }
}

resource "aws_vpc" "dev" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}

resource "aws_internet_gateway" "dev" { vpc_id = aws_vpc.dev.id }

resource "aws_subnet" "public" {
  for_each                = local.az_indices
  vpc_id                  = aws_vpc.dev.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, tonumber(each.key))
  map_public_ip_on_launch = true
  tags = { "kubernetes.io/role/elb" = "1" }
}

resource "aws_subnet" "private" {
  for_each                = local.az_indices
  vpc_id                  = aws_vpc.dev.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 3, 2 + tonumber(each.key))
  map_public_ip_on_launch = false
  tags = { "kubernetes.io/role/internal-elb" = "1" }
}
```

Use a single `aws_route_table.public`, two `aws_route_table.private` resources keyed by `local.az_indices`, four `aws_route_table_association` resources, `aws_route.public_default`, and `aws_route.private_default` keyed by `local.az_indices`. Associate public subnets with the public table, private subnets with their same-key private table, route public default traffic to `aws_internet_gateway.dev.id`, and route private default traffic to `aws_nat_gateway.lab[0].id`.

Create the NAT only in the first public subnet:

```hcl
resource "aws_eip" "nat" { domain = "vpc" }

resource "aws_nat_gateway" "lab" {
  count         = 1
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["0"].id
  depends_on    = [aws_internet_gateway.dev]
}
```

Create the endpoint and no Interface endpoint:

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.dev.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for route_table in aws_route_table.private : route_table.id]
}
```

Create `aws_security_group.eks_future` in the VPC with no `ingress` blocks and exactly one all-protocol egress block (`protocol = "-1"`, `cidr_blocks = ["0.0.0.0/0"]`). Do not add an SSH rule.

Append this non-sensitive output to `outputs.tf` once the referenced resources exist:

```hcl
output "network_contract" {
  description = "Non-sensitive topology contract for the future EKS foundation."
  value = {
    vpc_cidr       = aws_vpc.dev.cidr_block
    selected_azs   = sort(local.selected_azs)
    nat_gateways   = length(aws_nat_gateway.lab)
    s3_endpoint    = aws_vpc_endpoint.s3.vpc_endpoint_type == "Gateway"
    private_subnet = alltrue([for subnet in aws_subnet.private : !subnet.map_public_ip_on_launch])
  }
}
```

- [ ] **Step 4: Verify the implementation is green without AWS credentials**

Run:

```bash
terraform -chdir=terraform/environments/dev fmt -recursive
terraform -chdir=terraform/environments/dev init -backend=false
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev test
```

Expected: formatting, validation and both mock-provider tests pass. Fix only test or implementation mismatches; do not weaken assertions.

- [ ] **Step 5: Commit the network resources**

```bash
git add terraform/environments/dev/network.tf terraform/environments/dev/test/network.tftest.hcl terraform/environments/dev/.terraform.lock.hcl
git diff --cached --check
git commit -m "feat: add cost-aware dev network"
```

### Task 3: Add an exact create-only network plan verifier

**Files:**
- Create: `scripts/verify-dev-network-plan.py`
- Create: `tests/terraform/test_verify_dev_network_plan.py`

**Interfaces:**
- Consumes: `terraform show -json dev-network.tfplan` through standard input.
- Produces: exactly `dev_network_plan_contract=PASS` for the approved 19-resource create-only graph; non-zero and `FAIL_<reason>` otherwise.

- [ ] **Step 1: Write failing verifier tests**

Create a Python `unittest` file patterned after `test_verify_bootstrap_plan.py`. Its `EXPECTED_COUNTS` must be:

```python
EXPECTED_COUNTS = {
    "aws_vpc": 1,
    "aws_internet_gateway": 1,
    "aws_subnet": 4,
    "aws_route_table": 3,
    "aws_route": 3,
    "aws_route_table_association": 4,
    "aws_eip": 1,
    "aws_nat_gateway": 1,
    "aws_vpc_endpoint": 1,
    "aws_security_group": 1,
}
```

Test four behaviours: accepts the exact type counts with `['create']`; rejects an added `aws_eks_cluster`; rejects any `['delete']`; rejects a missing private-route association. The test invokes `scripts/verify-dev-network-plan.py` with JSON on stdin and expects the exact pass line.

- [ ] **Step 2: Run the test and verify it fails because the script does not exist**

Run:

```bash
python3 -m unittest tests/terraform/test_verify_dev_network_plan.py -v
```

Expected: the acceptance test fails with a missing verifier file.

- [ ] **Step 3: Implement the verifier with `collections.Counter`**

Create `scripts/verify-dev-network-plan.py`. It must parse JSON, skip non-managed and `['no-op']` changes, fail on non-create actions, count resource types with `Counter`, compare exactly to `EXPECTED_COUNTS`, and print only `dev_network_plan_contract=PASS` on success. Invalid JSON, an unexpected type/count, and any non-create action must print `dev_network_plan_contract=FAIL_<reason>` to stderr and exit one.

- [ ] **Step 4: Run verifier tests and static checks**

Run:

```bash
python3 -m unittest tests/terraform/test_verify_dev_network_plan.py -v
python3 -m py_compile scripts/verify-dev-network-plan.py
```

Expected: four passing tests and no compiler output.

- [ ] **Step 5: Commit the plan guard**

```bash
git add scripts/verify-dev-network-plan.py tests/terraform/test_verify_dev_network_plan.py
git diff --cached --check
git commit -m "test: verify dev network plan"
```

### Task 4: Add sanitized AWS readback and operating documentation

**Files:**
- Create: `scripts/verify-dev-network.sh`
- Create: `tests/terraform/test-verify-dev-network.sh`
- Modify: `terraform/environments/dev/README.md`

**Interfaces:**
- Consumes: `AWS_PROFILE=agentops-lab-bootstrap`, region selectors and Terraform state; the script resolves resource IDs internally and emits only a PASS/FAIL line.
- Produces: `dev_network_readback=PASS` only when the live network matches the approved topology.

- [ ] **Step 1: Write mock AWS CLI tests for readback failures**

Create a Bash test modeled on `test-verify-state-bucket.sh`. The fake `aws` command must return sanitized fixtures for `ec2 describe-vpcs`, `describe-subnets`, `describe-route-tables`, `describe-nat-gateways`, `describe-vpc-endpoints`, and `describe-security-groups`.

Assert one passing topology and failure cases for: VPC CIDR mismatch, fewer than two AZs, public IP mapping in a private subnet, multiple NAT gateways, missing S3 endpoint association, and a security-group ingress rule with TCP port 22. The test must assert only the `dev_network_readback=PASS` or `FAIL_<reason>` output, never fixture identifiers.

- [ ] **Step 2: Run the test to verify it fails because the script does not exist**

Run:

```bash
bash tests/terraform/test-verify-dev-network.sh
```

Expected: the pass case fails due to missing `scripts/verify-dev-network.sh`.

- [ ] **Step 3: Implement the fail-closed readback script**

Create `scripts/verify-dev-network.sh` with `#!/usr/bin/env bash` and `set -euo pipefail`. It must:

1. reject static AWS credential environment variables;
2. obtain the VPC ID only from `terraform -chdir=terraform/environments/dev output -raw` or a local variable, never print it;
3. query the VPC and require `10.20.0.0/16`;
4. require exactly four subnets across two AZs, with exactly two public and two private classifications based on their route tables and `MapPublicIpOnLaunch` values;
5. require one available NAT gateway, one EIP association, and private default routes pointing to it;
6. require one `Gateway` S3 endpoint associated with both private route tables;
7. require future EKS subnet tags, common tags and no ingress rule on TCP 22;
8. print only `dev_network_readback=PASS` on success and `dev_network_readback=FAIL_<reason>` on stderr otherwise.

Do not put AWS IDs, EIPs, CIDRs returned by AWS, or full policy documents in output.

- [ ] **Step 4: Run readback tests and shell syntax checks**

Run:

```bash
bash -n scripts/verify-dev-network.sh
bash -n tests/terraform/test-verify-dev-network.sh
bash tests/terraform/test-verify-dev-network.sh
```

Expected: all mock cases pass and no shell syntax error occurs.

- [ ] **Step 5: Document exact safe operator sequence**

Append to `terraform/environments/dev/README.md`:

```text
1. Authenticate with both approved AWS SSO profiles and run scripts/aws-terraform-preflight.sh.
2. Export only AWS_PROFILE=agentops-lab-bootstrap, AWS_REGION=us-west-2 and AWS_DEFAULT_REGION=us-west-2.
3. Resolve STATE_BUCKET_NAME from the bootstrap output without printing it.
4. terraform init with -backend-config="bucket=$STATE_BUCKET_NAME".
5. Run fmt, validate, test, a saved plan, and the JSON plan verifier before any apply.
6. Apply the reviewed plan, run scripts/verify-dev-network.sh, then practice only for the approved duration.
7. For an approved short-lived lab teardown, run terraform destroy from this dev root; do not run destroy from bootstrap.
8. Unset AWS variables and run aws sso logout when finished.
```

State that one NAT Gateway is an hourly/data-processing cost and a single-AZ failure point.

- [ ] **Step 6: Commit readback and documentation**

```bash
git add scripts/verify-dev-network.sh tests/terraform/test-verify-dev-network.sh terraform/environments/dev/README.md
git diff --cached --check
git commit -m "test: read back dev network controls"
```

### Task 5: Execute the reviewed network lifecycle and capture evidence

**Files:**
- Create: `docs/evidence/v0.1/dev-network.md`

**Interfaces:**
- Consumes: all Task 1-4 tests, approved AWS SSO access and an explicit operator decision to incur the NAT cost.
- Produces: a remote S3 state containing the approved network or, after teardown, no `dev` network resources; sanitized evidence either way.

- [ ] **Step 1: Authenticate and enforce the preflight boundary**

Run:

```bash
aws sso login --profile agentops-lab-bootstrap
aws sso login --profile agentops-org-admin
export AWS_PROFILE=agentops-lab-bootstrap
export AWS_REGION=us-west-2
export AWS_DEFAULT_REGION=us-west-2
scripts/aws-terraform-preflight.sh
```

Expected: `aws_terraform_preflight=PASS`. Stop otherwise.

- [ ] **Step 2: Initialize and verify local Terraform contracts**

```bash
STATE_BUCKET_NAME="$(terraform -chdir=terraform/bootstrap output -raw state_bucket_name)"
test -n "$STATE_BUCKET_NAME"
export STATE_BUCKET_NAME
terraform -chdir=terraform/environments/dev init -backend-config="bucket=$STATE_BUCKET_NAME"
terraform -chdir=terraform/environments/dev fmt -check
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev test
```

Expected: all commands succeed without printing the bucket name.

- [ ] **Step 3: Save, review and verify the AWS plan before apply**

Run:

```bash
terraform -chdir=terraform/environments/dev plan -out=dev-network.tfplan
terraform -chdir=terraform/environments/dev show -json dev-network.tfplan | scripts/verify-dev-network-plan.py
```

Expected: `dev_network_plan_contract=PASS`. Review the human-readable plan and stop if it includes a resource outside the ten approved types or any destruction.

- [ ] **Step 4: Obtain an explicit operator approval immediately before creating the NAT Gateway**

Record the intended practice duration and the approval in the task conversation. Do not infer that a prior design approval authorizes the billable apply.

- [ ] **Step 5: Apply the reviewed plan and perform sanitized readback**

Run:

```bash
terraform -chdir=terraform/environments/dev apply dev-network.tfplan
scripts/verify-dev-network.sh
terraform -chdir=terraform/environments/dev state list >/dev/null
```

Expected: `dev_network_readback=PASS` and an accessible remote state. Stop on any failure; do not re-plan and apply automatically.

- [ ] **Step 6: Tear down only when explicitly approved**

Run only after the practice period and an explicit teardown decision:

```bash
terraform -chdir=terraform/environments/dev plan -destroy -out=dev-network-destroy.tfplan
terraform -chdir=terraform/environments/dev apply dev-network-destroy.tfplan
terraform -chdir=terraform/environments/dev state list
```

Expected: no remaining `aws_*` network resources. The built-in `terraform_data.backend_contract` may remain as the remote-backend proof. Never run `terraform destroy` from `terraform/bootstrap`.

- [ ] **Step 7: Capture sanitized evidence and clear local authentication**

Create `docs/evidence/v0.1/dev-network.md` with PASS/FAIL outcomes only, the one-NAT cost/availability tradeoff, the apply and optional destroy timestamps, and no AWS identifiers. Run the repository privacy scan. Then:

```bash
unset STATE_BUCKET_NAME AWS_PROFILE AWS_REGION AWS_DEFAULT_REGION
aws sso logout
```

- [ ] **Step 8: Commit evidence**

```bash
git add docs/evidence/v0.1/dev-network.md
git diff --cached --check
git commit -m "docs: record dev network evidence"
```

## Final Verification

- [ ] `terraform -chdir=terraform/environments/dev fmt -check` passes.
- [ ] `terraform -chdir=terraform/environments/dev validate` passes.
- [ ] `terraform -chdir=terraform/environments/dev test` passes.
- [ ] Python and Bash verifier tests pass.
- [ ] The real plan verifier reports `dev_network_plan_contract=PASS` before each apply.
- [ ] The real readback reports `dev_network_readback=PASS` after apply.
- [ ] No SSH ingress, Interface endpoints, EKS, EC2, ECR, load balancers or DynamoDB exist in the plan.
- [ ] Repository privacy and runtime-artifact scans pass.
- [ ] Any teardown is explicitly approved, applies only the reviewed `dev` destroy plan, and leaves bootstrap state intact.
