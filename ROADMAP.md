# AgentOps EKS Roadmap

This roadmap deliberately evolves **one codebase**. Each milestone has prerequisites, required capabilities, evidence to capture, and a Definition of Done.

## v0.1 — Foundation

**Goal:** create a reproducible AWS/EKS platform and deploy a small application through CI/CD.

Required capabilities:
- Terraform-managed networking, EKS, managed worker nodes and ECR.
- Kubernetes access through `kubectl`.
- FastAPI demo service packaged as a non-root container.
- Helm chart with Deployment, ClusterIP Service, probes and resource requests/limits.
- GitHub Actions pipeline for test → build → push → deploy → smoke test.
- GitHub Actions authenticates to AWS through OIDC; no static AWS access keys stored in GitHub.
- Remote Terraform state and documented teardown procedure.
- Architecture and cost-driver documentation.

**Exit condition:** a clean environment can be provisioned from code, a commit can produce a uniquely tagged image in ECR, Helm can deploy it to EKS, and a smoke test proves the workload is healthy.

Detailed plan: [docs/milestones/v0.1-foundation.md](docs/milestones/v0.1-foundation.md)

---

## v0.2 — Observable

**Goal:** make the application and platform diagnosable before adding AI reasoning.

Prerequisite: v0.1 Definition of Done is satisfied.

Required capabilities:
- OpenTelemetry Collector deployed to Kubernetes.
- FastAPI instrumentation for traces and application metrics.
- Centralized application logs.
- Kubernetes/platform metrics needed for incident diagnosis.
- Correlation between request, trace and log context where practical.
- At least one dashboard covering latency, traffic, errors and saturation/restarts.
- At least one alert that can trigger a reproducible incident scenario.
- Telemetry backend documented and replaceable; collector configuration stays vendor-neutral where practical.

**Exit condition:** a deliberately introduced latency/error/restart scenario can be detected and explained using captured telemetry without shelling blindly into containers.

Detailed requirements: [docs/milestones/v0.2-observability.md](docs/milestones/v0.2-observability.md)

---

## v0.3 — Intelligent / Read-only Agent

**Goal:** add an AI incident investigator that can collect evidence but cannot modify the cluster.

Prerequisite: reliable telemetry from v0.2.

Required capabilities:
- Separate `incident-agent` service and Kubernetes service account.
- Kubernetes RBAC restricted to required read verbs/resources.
- Read-only tools such as: list/get pods, deployments, events, logs and selected metrics.
- Provider abstraction for the LLM so model choice is not hard-coded into business logic.
- Structured incident result: probable cause, evidence, confidence, recommended next action.
- Tool-call audit log and traceability.
- Timeouts, maximum reasoning/tool iterations and error handling.
- Tests proving the agent lacks Kubernetes write permissions.

**Exit condition:** given at least two reproducible failure scenarios, the agent gathers evidence and produces a useful diagnosis while all attempted write operations are denied.

Detailed requirements: [docs/milestones/v0.3-readonly-agent.md](docs/milestones/v0.3-readonly-agent.md)

---

## v0.4 — Controlled Actions

**Goal:** allow limited remediation without giving the LLM direct write access.

Prerequisite: v0.3 diagnoses are reliable enough to demonstrate.

Required capabilities:
- Separate tool/execution gateway from the reasoning agent.
- Explicit action schema with resource, proposed change, reason, risk and expiry.
- Human approval required before every write action in this milestone.
- Separate Kubernetes identity for the executor with narrowly scoped write permissions.
- Initial allowlisted actions only, e.g. restart a deployment or change replicas inside the demo namespace.
- Idempotency and stale-approval protection.
- Complete audit trail from recommendation → approval/rejection → execution → verification.
- Agent cannot bypass the approval path.

**Exit condition:** the agent can recommend a remediation, a human can approve or reject it, only approved allowlisted actions execute, and the system verifies the result.

Detailed requirements: [docs/milestones/v0.4-controlled-actions.md](docs/milestones/v0.4-controlled-actions.md)

---

## v0.5 — Production-ready Controls

**Goal:** harden the reference architecture around identity, blast radius, failure handling, cost and operational control.

Prerequisite: controlled action path from v0.4.

Required capabilities:
- EKS Pod Identity (or a documented equivalent where required) for workloads needing AWS APIs; no embedded AWS credentials.
- Namespace/workload RBAC reviewed for least privilege.
- Kubernetes NetworkPolicies for agent, executor and application boundaries.
- Secrets retrieved through an approved secret-management path; no secrets committed to Git.
- Tool allowlist/policy enforcement and explicit blocked actions.
- Kill switch to stop new agent actions quickly.
- Rate, timeout, retry, reasoning-step and token/cost budgets.
- Auditability for identity, model calls, tool calls, approvals and changes.
- Container/image security checks and dependency scanning in CI.
- Failure/chaos scenarios: permission denied, tool timeout, unavailable dependency, malformed tool response and runaway-loop protection.
- Recovery and rollback procedure documented.

**Exit condition:** the reference implementation demonstrates least privilege, controlled network/tool boundaries, traceable actions, bounded failures and an operator-controlled stop mechanism.

Detailed requirements: [docs/milestones/v0.5-production-controls.md](docs/milestones/v0.5-production-controls.md)

---

## Release rule

A milestone is tagged only after its Definition of Done is demonstrated and documented. Suggested tags:

- `v0.1.0` Foundation
- `v0.2.0` Observable
- `v0.3.0` Read-only Agent
- `v0.4.0` Controlled Actions
- `v0.5.0` Production-ready Controls

Do not duplicate application code into version folders. Git tags/releases preserve historical versions; `docs/milestones/` preserves the design narrative.
