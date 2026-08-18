# AgentOps EKS Roadmap

This roadmap deliberately evolves **one codebase**. Each milestone has prerequisites, required capabilities, evidence to capture, and a Definition of Done.

## Architecture philosophy

The project follows **AI Platform from First Principles**:

```text
What problem are we solving?
        ↓
How does it work without AI?
        ↓
How do we automate it?
        ↓
Where does AI actually help?
        ↓
Where should AI NOT be used?
```

The durable rule is **Deterministic First — Inference When Necessary**. Observability and deterministic checks come before AI reasoning; privileged execution remains deterministic and policy-controlled; repeated AI behavior should graduate toward normal software when practical.

See [docs/instructor/first-principles.md](docs/instructor/first-principles.md).

---

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

**First-principles requirement:** be able to explain the infrastructure, artifact and deployment flows without relying on Terraform/Helm syntax as the explanation.

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

**First-principles requirement:** a human should be able to diagnose the reference incident using system evidence before an LLM is introduced.

**Exit condition:** a deliberately introduced latency/error/restart scenario can be detected and explained using captured telemetry without shelling blindly into containers.

Detailed requirements: [docs/milestones/v0.2-observability.md](docs/milestones/v0.2-observability.md)

---

## v0.3 — Intelligent / Read-only Agent

**Goal:** add deterministic-first incident diagnosis plus an AI investigator for cases where evidence remains ambiguous.

Prerequisite: reliable telemetry from v0.2.

Required capabilities:
- Deterministic pre-check layer for known, cheap-to-identify conditions.
- Explicit decision point that invokes the LLM only when rules/runbooks do not sufficiently resolve the incident.
- Separate `incident-agent` service and Kubernetes service account.
- Kubernetes RBAC restricted to required read verbs/resources.
- Read-only tools such as: list/get pods, deployments, events, logs and selected metrics.
- Provider abstraction for the LLM so model choice is not hard-coded into business logic.
- Structured incident result: probable cause, evidence, confidence, recommended next action.
- Tool-call audit log and traceability.
- Timeouts, maximum reasoning/tool iterations and error handling.
- Tests proving the agent lacks Kubernetes write permissions.
- Metrics comparing deterministic vs inference paths, including escalation rate, latency and token usage.

**Exit condition:** known scenarios can bypass unnecessary inference, ambiguous scenarios can escalate to the read-only agent, the resulting diagnosis is evidence-backed, and all attempted write operations from the agent identity are denied.

Detailed requirements: [docs/milestones/v0.3-readonly-agent.md](docs/milestones/v0.3-readonly-agent.md)

---

## v0.4 — Controlled Actions

**Goal:** allow limited remediation without giving the LLM direct write access.

Prerequisite: v0.3 diagnoses are reliable enough to demonstrate.

Required capabilities:
- Separate tool/execution gateway from the reasoning agent.
- Explicit typed action schema with resource, proposed change, reason, risk and expiry.
- Deterministic policy/validation before execution.
- Human approval required before every write action in this milestone.
- Separate Kubernetes identity for the executor with narrowly scoped write permissions.
- Initial allowlisted actions only, e.g. restart a deployment or change replicas inside the demo namespace.
- Idempotency and stale-approval protection.
- Complete audit trail from recommendation → approval/rejection → execution → verification.
- Agent cannot bypass the approval path or issue arbitrary commands.

**First-principles requirement:** AI may recommend an operation, but the operation itself is implemented as known deterministic code with explicit bounds and deterministic verification.

**Exit condition:** the agent can recommend a remediation, a human can approve or reject it, only approved allowlisted actions execute through the restricted deterministic executor, and the system verifies the result.

Detailed requirements: [docs/milestones/v0.4-controlled-actions.md](docs/milestones/v0.4-controlled-actions.md)

---

## v0.5 — Production-ready Controls

**Goal:** harden the reference architecture around identity, blast radius, failure handling, cost and operational control while making inference usage explicit and bounded.

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
- Measurements for deterministic diagnoses, AI escalations, tokens/cost per investigation, path latency and AI bypass rate.
- Review of repeated AI paths to identify candidates that should become code, policies, runbooks or workflows.

**Exit condition:** the reference implementation demonstrates least privilege, controlled network/tool boundaries, traceable actions, bounded failures, bounded inference cost, an operator-controlled stop mechanism, and evidence that AI is used only where it provides justified value.

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
