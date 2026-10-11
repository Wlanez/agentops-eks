# v0.1 Block A — AWS Foundation

Block A builds only the infrastructure substrate:

```text
Terraform state
      ↓
     VPC
  ┌────┴────┐
public    private
subnets   subnets
  │          │
 NAT     EKS workers
             │
          EKS API

+ ECR image registry
```

No application, Helm chart, CI/CD workflow, observability stack, or AI agent is introduced yet.

## First Principles

| Component | Problem | What Terraform automates | Proof | Main tradeoff | Why no AI |
|---|---|---|---|---|---|
| S3 state | Terraform needs durable memory | protected remote state storage | bucket/versioning/lock behavior | bootstrap starts locally | bookkeeping is deterministic |
| VPC | workloads need explicit network boundaries | subnets, routes, IGW, NAT | route/subnet inspection + node connectivity | one NAT reduces cost but is not HA | routing is deterministic |
| EKS | we need a Kubernetes control plane + compute | roles, cluster, nodes, add-ons | nodes `Ready`, system pods healthy | managed service cost/complexity | cluster lifecycle is deterministic |
| ECR | deployments need a traceable image registry | immutable registry + cleanup | repository exists; later image SHA is traceable | lab uses force-delete for teardown | artifact storage is deterministic |

The recurring question is not “how do I copy this Terraform?” It is “what system are these resources encoding, and how do I prove each layer works?”

## 1. Confirm the AWS identity

```bash
aws sts get-caller-identity
```

Do not provision infrastructure until the account and assumed identity are the ones you intend to use.

## 2. Prepare dev input

```bash
cp terraform/environments/dev/terraform.tfvars.example \
   terraform/environments/dev/terraform.tfvars
```

Replace the documentation-only CIDR in `terraform.tfvars` with your current public IPv4 address as `/32`.

For example, if your public address is `203.0.113.25`, the value would be:

```hcl
cluster_endpoint_public_access_cidrs = ["203.0.113.25/32"]
```

The EKS Kubernetes version is configurable. The repository currently defaults to `1.36`; confirm that the configured version is still supported by Amazon EKS before provisioning.

## 3. Bootstrap remote state

```bash
terraform -chdir=terraform/bootstrap init
terraform -chdir=terraform/bootstrap fmt -check
terraform -chdir=terraform/bootstrap validate
terraform -chdir=terraform/bootstrap plan
terraform -chdir=terraform/bootstrap apply
```

Capture:

```bash
terraform -chdir=terraform/bootstrap output
```

## 4. Initialize the dev backend

From the repository root:

```bash
STATE_BUCKET=$(terraform -chdir=terraform/bootstrap output -raw state_bucket_name)
STATE_REGION=$(terraform -chdir=terraform/bootstrap output -raw state_region)

terraform -chdir=terraform/environments/dev init \
  -backend-config="bucket=${STATE_BUCKET}" \
  -backend-config="region=${STATE_REGION}"
```

The backend itself already defines:

```text
key          = agentops-eks/dev/terraform.tfstate
encrypt      = true
use_lockfile = true
```

## 5. Validate before creating anything

```bash
terraform -chdir=terraform/environments/dev fmt -check
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev plan -out=block-a.tfplan
```

Invalid CIDRs and inconsistent node scaling bounds (`min <= desired <= max`) are rejected by Terraform input checks before provisioning.

Review the plan. Pay particular attention to resources that create recurring cost:

- Amazon EKS control plane.
- NAT gateway.
- EC2 managed worker nodes.

The lab deliberately uses one NAT gateway. A production reference architecture would normally revisit the availability design rather than treating one NAT as highly available.

## 6. Apply Block A

```bash
terraform -chdir=terraform/environments/dev apply block-a.tfplan
```

Do not interpret a successful `terraform apply` as proof that Kubernetes is healthy. Verify the resulting system.

## 7. Configure kubectl and prove EKS works

```bash
terraform -chdir=terraform/environments/dev output -raw update_kubeconfig_command
```

Run the returned command, then:

```bash
kubectl get nodes -o wide
kubectl get pods -A
```

Block A runtime evidence should show:

- expected managed nodes in `Ready` state,
- healthy Kubernetes system pods,
- no requirement to SSH into a worker node.

## 8. Inspect managed add-ons

```bash
terraform -chdir=terraform/environments/dev output core_addon_versions
```

The configuration manages:

- `vpc-cni`
- `kube-proxy`
- `coredns`

The add-on versions are resolved against the configured Kubernetes version instead of hard-coding an old build forever.

### CNI permission tradeoff

For v0.1, `AmazonEKS_CNI_Policy` is attached to the EC2 node role to keep the foundation understandable and reproducible. AWS recommends separating VPC CNI permissions from the general node role. A later hardening milestone will move AWS workload permissions toward a dedicated identity rather than pretending this lab simplification is the final production design.

## 9. Inspect ECR

```bash
terraform -chdir=terraform/environments/dev output -raw ecr_repository_url
```

The repository is prepared for the later workload block with:

- immutable tags,
- scan-on-push,
- AES256 encryption,
- cleanup of untagged images after seven days.

`force_delete = true` is intentional for this disposable lab so teardown is not blocked by demo images. A production repository would revisit deletion/retention policy.

## 10. Teardown

When the lab is not being used:

```bash
terraform -chdir=terraform/environments/dev destroy
```

This removes the cost-bearing dev infrastructure. The bootstrap state bucket is separately protected with `prevent_destroy` because deleting the state store is a different operational decision.

## Block A evidence checklist

Capture these while implementing rather than reconstructing them later:

- [ ] `aws sts get-caller-identity`
- [ ] `terraform fmt`, `init`, and `validate`
- [ ] successful bootstrap plan/apply
- [ ] successful dev `terraform plan`
- [ ] EKS nodes `Ready`
- [ ] healthy `kube-system` pods
- [ ] resolved managed add-on versions
- [ ] ECR repository configuration
- [ ] one real failure/troubleshooting lesson if naturally encountered
- [ ] observed cost drivers
- [ ] successful `terraform destroy` for the dev environment

**Do not mark Block A complete from source-code review alone.** The runtime checks above are part of the learning objective because the gap between desired configuration and observed system behavior is exactly what a platform engineer must understand.

## Stop boundary

Do **not** continue from Block A directly into AI.

The next v0.1 block is the workload path:

```text
FastAPI → container → ECR → Helm → EKS
```

Only after that path is understood and verified do we automate delivery with GitHub Actions.
