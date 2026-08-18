# agentops-eks

Production-style reference project for running **observable, controlled AI agents on Amazon EKS**.

The project evolves one codebase through five milestones. Each milestone must produce reusable evidence for GitHub, CV/interviews, technical content, and consulting demos.

## Core idea

Start with a small application running reliably on EKS, make it observable, add a read-only incident investigation agent, then introduce human-approved actions and production controls.

```text
EKS workload
    ↓
Observable
    ↓
AI-assisted
    ↓
Human-controlled
    ↓
Production-ready
```

## AI Platform from First Principles

This project is deliberately **not** a copy/paste AI tutorial.

Every milestone should be explained through the same sequence:

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

The durable engineering principle is:

> **Deterministic First — Inference When Necessary.**

We want engineers to understand the system before outsourcing reasoning to an LLM. Stable, repeated behavior should become normal code, policies, runbooks or workflows when practical; inference should be reserved for ambiguity and reasoning where it adds real value.

See [AI Platform from First Principles](docs/instructor/first-principles.md).

## Milestones

| Version | Capability | Outcome |
|---|---|---|
| v0.1 | Foundation | Reproducible EKS platform + demo app + CI/CD |
| v0.2 | Observable | Metrics, logs and traces across app/platform |
| v0.3 | Intelligent | Deterministic-first diagnosis + read-only AI investigation for ambiguous incidents |
| v0.4 | Controlled | AI recommendation + policy + human approval + restricted deterministic executor |
| v0.5 | Production-ready | Identity, policies, kill switch, inference/cost bounds, reliability controls and security hardening |

See [ROADMAP.md](ROADMAP.md) and [docs/requirements.md](docs/requirements.md).

## Repository structure

```text
agentops-eks/
├── README.md
├── ROADMAP.md
├── docs/
│   ├── requirements.md
│   ├── milestones/
│   └── instructor/
├── terraform/
├── helm/
├── services/
├── observability/
├── security/
├── scenarios/
├── tests/
└── .github/workflows/
```

Folders are added as the corresponding milestone is implemented. Versions are preserved with Git tags/releases rather than duplicated version folders.

## Current target

**v0.1 Foundation** — provision the AWS/EKS foundation, containerize a small FastAPI workload, deploy it with Helm, and automate build/deploy with GitHub Actions.

## Instructor / teaching material

This repository is also the instructor/reference implementation. Teaching notes are intentionally kept separate from the engineering milestone requirements.

- [Instructor notes](docs/instructor/README.md)
- [AI Platform from First Principles](docs/instructor/first-principles.md)
- [v0.1 Foundation teaching guide](docs/instructor/v0.1-teaching-guide.md)

The instructor material captures mental models, Mermaid diagrams, teaching order, common misconceptions, verification evidence, troubleshooting lessons, video structure, and the information that can later be extracted into a separate student/template repository.

The rule is: **build the real milestone first, capture what was difficult, then simplify that experience for the student.**

## Engineering principles

- **First principles before frameworks:** understand the problem and system model before choosing tools.
- **Deterministic first, inference when necessary:** do not spend tokens on behavior normal software can implement reliably.
- **Evidence before inference:** observability and system state should feed reasoning instead of vague prompts.
- **AI proposes; deterministic systems execute:** privileged actions go through typed operations, policy and verification.
- Infrastructure as Code before console-only configuration.
- No long-lived AWS keys in GitHub Actions.
- Least privilege by default.
- Immutable container image tags for deployments.
- Health/readiness probes and resource requests/limits from the first workload.
- Every milestone has an explicit Definition of Done.
- Keep the lab reproducible and disposable; document teardown and expected cost drivers.
- AI agents never receive unrestricted Kubernetes administrator access.
- Optimize for day-300 maintainability, not only a successful demo.

## License

Apache-2.0.
