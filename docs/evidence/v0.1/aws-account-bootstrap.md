# AWS Account Bootstrap Evidence

**Completed:** 2026-08-25
**Region:** us-west-2

## Verified controls

- [x] AWS Organization uses all features.
- [x] Workloads are isolated in the agentops-lab member account.
- [x] IAM Identity Center uses an organization instance.
- [x] The intended human identity is jorge.nunez; no accidental account-named user or permission-set-named group remains.
- [x] Human access uses MFA and temporary SSO credentials.
- [x] Root MFA remains enabled and root has no access keys.
- [x] OrganizationAdmin is assigned only to the management account and is not used for AgentOps workloads.
- [x] AgentOpsBootstrapAdmin and AgentOpsReadOnly are assigned only to agentops-lab.
- [x] The read-only role passed a negative write-permission test.
- [x] AWS CLI profiles returned the intended account and permission-set roles.
- [x] The management account contains no AgentOps workloads.
- [x] Monthly budget alerts are configured at USD 10, USD 20, and USD 30.
- [x] Cost Anomaly Detection has a USD 5 notification threshold.

## Credential model

Human users authenticate through IAM Identity Center. No long-lived AWS access keys are used. GitHub Actions OIDC will be implemented in a later v0.1 workstream.

## Privacy

Account IDs, emails, portal URLs, role ARNs, tokens, MFA material, and credential cache contents are intentionally excluded.
