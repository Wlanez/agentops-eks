# Global Requirements

These requirements apply across the AgentOps EKS roadmap unless a milestone explicitly changes them.

## Accounts and access

- AWS account with permission to create/manage EKS, EC2/VPC networking, IAM roles/policies, ECR and the resources used by the selected telemetry backend.
- GitHub repository with Actions enabled.
- A dedicated AWS region configured through variables; avoid hard-coding region-specific values.
- Separate local/developer identity from workload identities.

## Local tooling

Required for v0.1 development and verification:

- Git
- Docker-compatible container runtime
- AWS CLI v2
- `kubectl`
- Terraform
- Helm 3
- Python 3.x for the demo FastAPI service and tests
- `make` optional but recommended for repeatable developer commands

Pin tool/provider/module versions in code or documented dev tooling rather than relying silently on whatever is newest on a workstation.

## AWS / Kubernetes baseline

- Use an Amazon EKS Kubernetes version currently supported by AWS at implementation time.
- Use Linux EC2 managed nodes for the baseline reference implementation.
- Nodes run in private subnets for the reference architecture; v0.1 may use a cost-aware single-NAT lab profile, documented as non-HA.
- Public-facing and private networking decisions must be explicit in Terraform variables/documentation.
- No inbound SSH to worker nodes is required for normal operation.
- Kubernetes workloads use dedicated service accounts once they require distinct permissions.

## Infrastructure as Code

- Terraform owns cloud infrastructure used by the project.
- Remote state is required before v0.1 is considered complete.
- State locking/protection uses a mechanism supported by the selected Terraform S3 backend configuration.
- Formatting and validation run before infrastructure changes.
- Destructive teardown is documented and tested for the lab environment.

## CI/CD authentication

- GitHub Actions uses GitHub OIDC federation to assume an AWS IAM role.
- Do not store long-lived AWS access-key/secret-key pairs as repository Actions secrets.
- CI permissions must be narrower than administrator/root permissions.
- Deployment artifacts are traceable to source commits.

## Container baseline

- Non-root runtime user when practical.
- Small, reproducible image build.
- Image tagged with immutable identifier (commit SHA or equivalent); `latest` is not the deployment source of truth.
- ECR is the baseline container registry.
- Container exposes health/readiness behavior needed by Kubernetes.

## Kubernetes workload baseline

Every application workload should have:

- Namespace
- Deployment
- Service
- Liveness and readiness probes
- CPU/memory requests and limits
- Labels/annotations that support operations and telemetry
- Rolling-update behavior documented
- No embedded cloud credentials

## Security principles

- Least privilege for AWS IAM and Kubernetes RBAC.
- No secrets committed to Git.
- No AI agent receives `cluster-admin`.
- Reasoning and privileged execution are separate responsibilities by v0.4.
- Every privileged action must be attributable to an identity and auditable by v0.5.

## Observability principles

Starting in v0.2:

- OpenTelemetry is the default instrumentation/collection layer.
- Metrics, logs and traces should be correlated where practical.
- Agent operations add their own telemetry: model/tool latency, tool errors, execution state and approvals.
- Telemetry backend choice should not leak unnecessarily into application code.

## Cost / lab hygiene

EKS, worker nodes, NAT gateways, load balancers and telemetry services can generate continuous AWS cost.

For a portfolio lab:

- Document expected cost drivers.
- Prefer variable-driven sizes and counts.
- Provide a reliable `terraform destroy` path.
- Avoid creating expensive add-ons before the milestone requires them.
- Treat cost control as part of the architecture, not an afterthought.

## Documentation/evidence requirement

Each milestone should capture:

1. Architecture diagram or clear text diagram.
2. What problem the milestone solves.
3. Key design decisions/tradeoffs.
4. Commands or automation to reproduce it.
5. Evidence that the Definition of Done works.
6. What is intentionally out of scope until the next milestone.

That evidence is what turns the repository into a reusable portfolio, interview and consulting asset.
