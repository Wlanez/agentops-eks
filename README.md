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

## Milestones

| Version | Capability | Outcome |
|---|---|---|
| v0.1 | Foundation | Reproducible EKS platform + demo app + CI/CD |
| v0.2 | Observable | Metrics, logs and traces across app/platform |
| v0.3 | Intelligent | Read-only incident agent gathers evidence and recommends actions |
| v0.4 | Controlled | Human approval + restricted executor for write actions |
| v0.5 | Production-ready | Identity, policies, kill switch, cost/reliability controls and security hardening |

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
- [v0.1 Foundation teaching guide](docs/instructor/v0.1-teaching-guide.md)

The instructor material captures mental models, Mermaid diagrams, teaching order, common misconceptions, verification evidence, troubleshooting lessons, video structure, and the information that can later be extracted into a separate student/template repository.

The rule is: **build the real milestone first, capture what was difficult, then simplify that experience for the student.**

## Engineering principles

- Infrastructure as Code before console-only configuration.
- No long-lived AWS keys in GitHub Actions.
- Least privilege by default.
- Immutable container image tags for deployments.
- Health/readiness probes and resource requests/limits from the first workload.
- Every milestone has an explicit Definition of Done.
- Keep the lab reproducible and disposable; document teardown and expected cost drivers.
- AI agents never receive unrestricted Kubernetes administrator access.

## License

Apache-2.0.
