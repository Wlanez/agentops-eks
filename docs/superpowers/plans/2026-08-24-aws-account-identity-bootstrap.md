# AWS Account and Identity Bootstrap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Configure a secure two-account AWS organization with IAM Identity Center, temporary human credentials, verified permission sets, and cost controls before AgentOps infrastructure is created.

**Architecture:** The existing standalone account becomes the AWS Organizations management account and contains only organization, identity, and consolidated billing services. A new member account named `agentops-lab` contains all future Terraform, VPC, EKS, ECR, observability, and agent workloads. Human access uses IAM Identity Center; machine access will use GitHub OIDC in a later v0.1 workstream.

**Tech Stack:** AWS Organizations, AWS IAM Identity Center, AWS managed permission policies, AWS CLI v2 SSO token provider, AWS Budgets, AWS Cost Explorer, AWS Cost Anomaly Detection.

**Spec:** `docs/superpowers/specs/2026-08-24-aws-account-identity-bootstrap-design.md`

## Global Constraints

- IAM Identity Center home region: `us-west-2`.
- Member account name: `agentops-lab`.
- Human Identity Center username: `jorge.nunez`.
- Root MFA remains enabled and root access keys remain absent.
- Never paste account emails, account IDs, portal URLs, passwords, MFA seeds, tokens, or credentials into GitHub or chat.
- No IAM user or long-lived AWS access key may be created.
- Management account contains no AgentOps workloads.
- Monthly consolidated cost budget: USD 30.
- Actual-cost notifications: USD 10, USD 20, and USD 30.
- Forecasted-cost notification: USD 30; it may remain inactive until AWS has enough history.
- Cost anomaly notification threshold: USD 5.
- No Terraform, VPC, EKS, ECR, NAT gateway, load balancer, or application resource is created by this plan.
- Stop immediately on unexpected account ownership, unexpected existing resources, permission errors that imply the wrong identity, or any request to expose credentials.
- Use the AWS console labels shown in the current UI; when AWS changes a label, preserve the named resource and verification outcome in this plan.

## Required object and naming map

Read this table before creating any identity, group, permission set, account, SSO session, or CLI profile.

| Object type | Exact name | Purpose |
|---|---|---|
| AWS Organizations management account | existing account name | Organization, Identity Center, billing, and budgets |
| AWS Organizations member account | `agentops-lab` | Terraform, EKS, ECR, observability, and agent workloads |
| IAM Identity Center human user | `jorge.nunez` | The only human directory identity created by this plan |
| IAM Identity Center management group | `OrganizationAdministrators` | Grants management-account access to its members |
| IAM Identity Center lab group | `AgentOpsAdministrators` | Grants lab access to its members |
| Management permission set | `OrganizationAdmin` | Administrator role in the management account |
| Lab permission sets | `AgentOpsBootstrapAdmin`, `AgentOpsReadOnly` | Administrator and inspection roles in the lab account |
| Local AWS CLI SSO session | `agentops-sso` | Shared browser authentication for all three CLI profiles |
| Local AWS CLI profiles | `agentops-org-admin`, `agentops-lab-bootstrap`, `agentops-lab-readonly` | Select the intended account and permission-set role |

Rules:

- An **AWS account** is created under AWS Organizations. It is not an IAM Identity Center user or group.
- A **user or group** answers *who receives access*. A **permission set** answers *what that principal can do in one assigned AWS account*.
- Never create a user named `agentops-lab`, `OrganizationAdmin`, `AgentOpsBootstrapAdmin`, or `AgentOpsReadOnly`.
- Never create a group named after a permission set. This plan uses only `OrganizationAdministrators` and `AgentOpsAdministrators`.
- `Provisioned` on a permission set means its AWS-managed role exists in an account. It does not prove that `jorge.nunez` received access.
- Stop whenever an object appears under the wrong console area or with the wrong type. Do not compensate by creating another similarly named object.

## Files Created by Execution

- Create: `docs/evidence/v0.1/aws-account-bootstrap.md` — sanitized evidence and completed checklist after AWS configuration succeeds.
- Do not create credential files inside the repository.
- Local AWS CLI configuration remains in the normal AWS CLI user configuration location and is not committed.

---

### Task 1: Establish the root-session safety checkpoint and create the organization

**Interfaces:**
- Consumes: secured standalone AWS account with root MFA and no root access keys.
- Produces: AWS Organization using all features, with the current account as management account.

- [x] **Step 1: Start a private root console session**

Open the AWS sign-in page in a private browser window, choose **Root user**, authenticate with the existing root email, password, and MFA.

Do not save the root password in the browser and do not create access keys.

- [x] **Step 2: Reconfirm root security**

Open **IAM → Dashboard → Security recommendations** and confirm:

- MFA is enabled for root.
- No root access key exists.

Expected: root security shows MFA protection and no active root access keys.

Stop if either condition is false.

- [x] **Step 3: Create the organization**

Open **AWS Organizations** and choose **Create an organization**.

Use the default **All features** mode. Do not select consolidated-billing-only mode.

Official reference: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_org_create.html

Expected: the Organizations account list contains one account marked **Management account** and the feature set is **All features**.

- [x] **Step 4: Complete email verification when requested**

Open the verification email sent to the management account address and complete verification within the validity period.

Return to **AWS Organizations → Settings**.

Expected: organization email verification is complete and **All features** remains enabled.

- [x] **Step 5: Activate IAM role access to Billing information**

While still signed in as root, open the account menu and choose **Account**.

Under **IAM User and Role Access to Billing Information**, choose **Edit**, enable **Activate IAM Access**, and save.

This setting does not grant billing permissions by itself. It allows IAM roles that already have suitable policies—including the later `OrganizationAdmin` role—to open the applicable Billing and Cost Management console pages. AWS requires root to change this setting, and `AdministratorAccess` cannot enable it.

Enable it only in the management account for this bootstrap. The member account does not need Billing console access yet.

Official reference: https://docs.aws.amazon.com/cost-management/latest/userguide/control-access-billing.html

Expected: **IAM User and Role Access to Billing Information** is activated in the management account.

Stop if the setting cannot be confirmed; otherwise Task 9 can later fail even when `OrganizationAdmin` has administrator permissions.

- [x] **Step 6: Record only non-sensitive checkpoint data**

Record privately, outside Git:

- management account ID;
- organization ID;
- management root email;
- verification date.

Do not copy these values into the project evidence file.

### Task 2: Enable the organization instance of IAM Identity Center

**Interfaces:**
- Consumes: AWS Organization with all features.
- Produces: one organization instance of IAM Identity Center in `us-west-2`.

- [x] **Step 1: Select the home region**

In the AWS console region selector, choose **US West (Oregon) — us-west-2**.

This selection defines the IAM Identity Center home region for this organization instance. It is separate from the region selected later by an individual workload profile, even though both are intentionally `us-west-2` in this project.

- [x] **Step 2: Enable IAM Identity Center**

Open **IAM Identity Center** and choose **Enable**.

On the instance selection page, choose the option that enables IAM Identity Center **with AWS Organizations**. Do not choose an account instance.

Official reference: https://docs.aws.amazon.com/singlesignon/latest/userguide/enable-identity-center.html

Expected: IAM Identity Center shows an **Organization instance** and exposes **Multi-account permissions**.

Stop if the console describes the instance as **Account instance**.

- [x] **Step 3: Verify the built-in directory**

Open **IAM Identity Center → Settings → Identity source**.

Expected: the identity source is **Identity Center directory**.

Do not connect Google Workspace, Microsoft Entra ID, Active Directory, or another IdP in this bootstrap.

- [x] **Step 4: Configure MFA enforcement**

Open **Settings → Authentication → Multi-factor authentication → Configure**.

Set:

- Prompt for MFA: **Every time they sign in**.
- Users without a registered device: **Require them to register an MFA device at sign in**.
- Device management: **Users can add and manage their own MFA devices**.
- Allowed methods: prefer passkeys/security keys when available; keep authenticator app enabled as the practical fallback.

Official references:

- https://docs.aws.amazon.com/singlesignon/latest/userguide/mfa-getting-started.html
- https://docs.aws.amazon.com/singlesignon/latest/userguide/how-to-configure-mfa-device-enforcement.html

Expected: MFA is required and self-enrollment is enabled.

- [x] **Step 5: Locate, test, and record the access portal URL privately**

While still in the management-account console and `us-west-2`, open:

**IAM Identity Center → Dashboard → Settings summary**

Locate **AWS access portal URL** and copy its exact value. This value is also called the **SSO Start URL** by the AWS CLI.

Open the copied URL in a private browser tab. At this stage, it is sufficient to confirm that the IAM Identity Center sign-in page loads; the `jorge.nunez` user is activated and fully tested later in Task 5.

Expected:

- the URL shown comes from the organization instance in `us-west-2`;
- opening it displays the IAM Identity Center sign-in page;
- the address normally identifies the access portal and ends with `/start`, unless a supported custom portal URL is later configured.

Save the exact URL in the user's password manager or another private location under a recognizable name such as `AWS AgentOps SSO Start URL`.

Do not place the real URL in GitHub, the evidence document, screenshots, terminal transcripts, or chat.

Do not confuse the access portal URL with:

- an AWS Management Console service URL;
- an account-specific console link;
- the temporary OIDC authorization URL printed by `aws sso login`, which contains `/authorize` and expires.

Official reference: https://docs.aws.amazon.com/singlesignon/latest/userguide/howtosigninprocedure.html

### Task 3: Create the human identity and management group

**Interfaces:**
- Consumes: Identity Center directory.
- Produces: `jorge.nunez` in `OrganizationAdministrators`, with invitation sent.

- [x] **Step 1: Create the group**

Open **IAM Identity Center → Groups → Create group**.

Set:

- Group name: `OrganizationAdministrators`
- Description: `Administrators for AWS Organizations, Identity Center, and consolidated billing.`

Choose **Create group**.

Expected: the group exists with zero users.

- [x] **Step 2: Create the user**

Open **Users → Add user**.

Set:

- Username: `jorge.nunez`
- Email: the private user email selected for Identity Center access
- First name: `Jorge`
- Last name: `Núñez`
- Display name: `Jorge Núñez`
- Send email with password setup instructions: enabled

The invitation expires after seven days; complete activation during this execution.

`jorge.nunez` is an IAM Identity Center directory user, not an IAM user inside either AWS account. Do not create a similarly named IAM user or access keys.

Official reference: https://docs.aws.amazon.com/singlesignon/latest/userguide/addusers.html

- [x] **Step 3: Add the user to the group**

During user creation, select `OrganizationAdministrators`, or afterward open:

**Groups → OrganizationAdministrators → Add users to group**

Select `jorge.nunez` and choose **Add users**.

Expected: group membership shows `jorge.nunez`.

- [x] **Step 4: Verify the initial identity inventory**

Open **IAM Identity Center → Users**.

Expected at this stage: the only human directory user created by this plan is `jorge.nunez`.

Then open **IAM Identity Center → Groups**.

Expected at this stage:

- `OrganizationAdministrators` exists and contains `jorge.nunez`;
- `AgentOpsAdministrators` does not exist yet; it is created in Task 7;
- no user or group is named `agentops-lab`, `OrganizationAdmin`, `AgentOpsBootstrapAdmin`, or `AgentOpsReadOnly`.

Stop if an account name or permission-set name appears as a user or group. Record the unexpected object privately and use the recovery checkpoint in Task 8 Step 7 after the correct access path is verified.

### Task 4: Create and assign management-account access

**Interfaces:**
- Consumes: management group and management account.
- Produces: `OrganizationAdmin` permission set assigned through the group.

- [x] **Step 1: Create the permission set**

Open **IAM Identity Center → Multi-account permissions → Permission sets → Create permission set**.

Choose **Predefined permission set**, select the AWS managed policy `AdministratorAccess`, and set:

- Permission set name: `OrganizationAdmin`
- Description: `Organization, identity, account, and consolidated billing administration only.`
- Session duration: `1 hour`

Official reference: https://docs.aws.amazon.com/singlesignon/latest/userguide/howtocreatepermissionset.html

Expected: permission-set details show `AdministratorAccess` and a one-hour session.

Important authorization boundary: `AdministratorAccess` grants administrative access to all supported services inside the account where the permission set is assigned. The name and description do not technically restrict it to Organizations or Billing. Isolation comes from assigning `OrganizationAdmin` only to the management account and prohibiting project workloads there.

- [x] **Step 2: Assign the group to the management account**

Open **Multi-account permissions → AWS accounts**.

Select the management account, choose **Assign users or groups**, select **Groups**, choose `OrganizationAdministrators`, and assign `OrganizationAdmin`.

Official reference: https://docs.aws.amazon.com/singlesignon/latest/userguide/assignusers.html

Expected: the management account assignments show the group and permission set.

- [x] **Step 3: Wait for provisioning**

Wait until the assignment status is successful.

Do not continue while the console shows provisioning in progress or failed.

### Task 5: Activate the Identity Center user and stop using root

**Interfaces:**
- Consumes: user invitation and management assignment.
- Produces: verified MFA-protected portal access as `jorge.nunez`.

- [x] **Step 1: Accept the invitation**

Open the invitation email with subject similar to **Invitation to join AWS IAM Identity Center**.

Choose **Accept invitation**, create a unique password, and register an MFA device.

Expected: the AWS access portal opens after successful activation.

- [x] **Step 2: Verify management-account access**

In the access portal, select the management account and open `OrganizationAdmin`.

Open **AWS Organizations** and confirm the organization is visible.

Expected: console access works as the Identity Center role.

- [x] **Step 3: End the root session**

Return to the root browser window, sign out, and close the private window.

From this point onward, use `OrganizationAdmin`. Root is used again only for a documented root-only operation.

- [x] **Step 4: Confirm the signed-in role**

In the management console, open the account menu.

Expected: the role name contains the Identity Center-generated role for `OrganizationAdmin`, not **Root user**.

Stop if the active principal is root.

### Task 6: Create the `agentops-lab` member account

**Interfaces:**
- Consumes: `OrganizationAdmin` access and the distinct private business email.
- Produces: active member account with default `OrganizationAccountAccessRole`.

- [x] **Step 1: Start member-account creation**

Using the Identity Center `OrganizationAdmin` session, open:

**AWS Organizations → AWS accounts → Add an AWS account → Create an AWS account**

Set:

- AWS account name: `agentops-lab`
- Owner email: the distinct private business email controlled by the user
- IAM role name: leave blank so AWS creates `OrganizationAccountAccessRole`

This workflow creates an **AWS account**. Remain under **AWS Organizations**. Do not open IAM Identity Center **Users** or create a directory user named `agentops-lab`.

Before choosing **Create AWS account**, confirm that the page asks for an account name and owner email—not a username, first name, last name, or password.

Official reference: https://docs.aws.amazon.com/organizations/latest/userguide/orgs_manage_accounts_create.html

- [x] **Step 2: Wait for account creation**

Monitor the request until the account status is **ACTIVE**.

Account creation is asynchronous. Do not submit another request if the first remains in progress.

Stop and investigate if status becomes **FAILED**; common causes include an email already associated with another AWS account or account-creation quotas.

- [x] **Step 3: Verify organization topology**

Open **AWS Organizations → AWS accounts**.

Expected:

- one management account;
- one member account named `agentops-lab`;
- member status **ACTIVE**.

Record the member account ID privately outside Git.

- [x] **Step 4: Do not initialize member root credentials**

Do not run password recovery or create member-account root credentials. Normal access will come from IAM Identity Center.

`OrganizationAccountAccessRole` and the IAM Identity Center roles are different mechanisms. The former is created by AWS Organizations for management-account administration; it is not one of the human CLI profiles in this plan. Do not create static credentials or configure a normal working profile around it.

### Task 7: Create and assign lab permission sets

**Interfaces:**
- Consumes: active `agentops-lab` member account and `jorge.nunez`.
- Produces: bootstrap-admin and read-only portal roles in the member account.

- [x] **Step 1: Create the lab group**

Open **IAM Identity Center → Groups → Create group**.

Set:

- Group name: `AgentOpsAdministrators`
- Description: `Human administrators for the disposable agentops-lab environment.`

Add `jorge.nunez` to the group.

Expected: group membership contains exactly the intended user.

Do not create a group named `AgentOpsReadOnly` or `AgentOpsBootstrapAdmin`. Those names belong to permission sets created in the next steps, not to groups.

- [x] **Step 2: Create `AgentOpsBootstrapAdmin`**

Open **Permission sets → Create permission set**.

Choose **Predefined permission set**, select `AdministratorAccess`, and set:

- Name: `AgentOpsBootstrapAdmin`
- Description: `Temporary bootstrap administration for AgentOps v0.1 foundations.`
- Session duration: `1 hour`

Expected: permission set shows `AdministratorAccess`.

- [x] **Step 3: Create `AgentOpsReadOnly`**

Create another predefined permission set using the AWS managed policy `ReadOnlyAccess`.

Set:

- Name: `AgentOpsReadOnly`
- Description: `Read-only inventory and diagnosis in agentops-lab.`
- Session duration: `1 hour`

Expected: permission set shows `ReadOnlyAccess`.

- [x] **Step 4: Assign the lab account to the group with both permission sets**

Open **IAM Identity Center → Multi-account permissions → AWS accounts**.

In the organization tree:

1. Select the checkbox immediately to the left of `agentops-lab`.
2. Choose **Assign users or groups**.
3. On **Step 1: Select users and groups**, open the **Groups** tab.
4. Select exactly `AgentOpsAdministrators`.
5. Expand the selection summary and confirm **Selected groups (1)** contains `AgentOpsAdministrators`.
6. Do not select the **Users** tab and do not select or create a user named `agentops-lab`.
7. Choose **Next**.
8. Select both `AgentOpsBootstrapAdmin` and `AgentOpsReadOnly`.
9. Choose **Next**.
10. Review this exact relationship:

```text
AWS account: agentops-lab
Group: AgentOpsAdministrators
Permission sets:
- AgentOpsBootstrapAdmin
- AgentOpsReadOnly
```

11. Choose **Submit** and leave the page open until AWS reports that all assignments were configured successfully.

A green `Provisioned` status alone does not prove that the intended group received access.

Official reference: https://docs.aws.amazon.com/singlesignon/latest/userguide/assignusers.html

- [x] **Step 5: Verify the group-to-account assignment**

Open **IAM Identity Center → Groups → AgentOpsAdministrators → AWS accounts**.

Select `agentops-lab` under **AWS account access**.

Expected: **Applied permission sets (2)** contains `AgentOpsBootstrapAdmin` and `AgentOpsReadOnly`.

If the account is absent or only one permission set appears, return to Step 4 and add only the missing assignment. Do not create another user, group, or permission set.

- [x] **Step 6: Verify inherited access on the intended user**

Open **IAM Identity Center → Users → jorge.nunez → AWS accounts**.

Expected:

- the management account displays `OrganizationAdmin`;
- `agentops-lab` displays `AgentOpsBootstrapAdmin` and `AgentOpsReadOnly`;
- no lab access depends on a directory user named `agentops-lab`.

This page is the decisive administrative proof that group membership produced the intended access.

- [x] **Step 7: Verify the real AWS access portal and console launch**

Sign out of any existing portal session. Open a new private browser window, navigate to the private access portal URL ending in `/start`, and sign in as `jorge.nunez`.

Do not use the IAM Identity Center administrative console for this test. The real page heading is **AWS access portal** and displays an **AWS accounts** count.

Confirm:

- **AWS accounts (2)** is displayed;
- the management account displays `OrganizationAdmin`;
- `agentops-lab` displays `AgentOpsBootstrapAdmin` and `AgentOpsReadOnly`;
- all three roles open their intended consoles.

Do not continue to Task 8 if the portal shows one account or a role is absent. The problem is still in the user, group, assignment, provisioning, or portal-session layer—not in the CLI.

### Task 8: Configure temporary AWS CLI SSO profiles

**Interfaces:**
- Consumes: AWS CLI v2, access portal start URL, `us-west-2`, and provisioned permission sets.
- Produces: three named local SSO profiles with no static credentials.

#### Understand `sso-session` versus `profile`

The AWS CLI stores two related kinds of local configuration:

- `[sso-session agentops-sso]` identifies the IAM Identity Center portal, its home region, and the browser authentication token.
- each `[profile ...]` selects one AWS account and one assigned permission-set role.

The session name is only a local label. It is not an AWS account, IAM Identity Center user, permission set, or IAM role, and its name cannot grant or deny access. This plan uses `agentops-sso` because the same authentication session serves both the management and lab accounts.

A previous session name such as `agentops-lab` is technically valid but misleading. It does not itself explain a `ForbiddenException: No access`. For consistency, the completed configuration should use one shared session named `agentops-sso`.

The expected structure in `~/.aws/config` is conceptually:

```ini
[sso-session agentops-sso]
sso_start_url = <PRIVATE_ACCESS_PORTAL_URL>
sso_region = us-west-2
sso_registration_scopes = sso:account:access

[profile agentops-org-admin]
sso_session = agentops-sso
sso_account_id = <MANAGEMENT_ACCOUNT_ID>
sso_role_name = OrganizationAdmin
region = us-west-2
output = json

[profile agentops-lab-bootstrap]
sso_session = agentops-sso
sso_account_id = <LAB_ACCOUNT_ID>
sso_role_name = AgentOpsBootstrapAdmin
region = us-west-2
output = json

[profile agentops-lab-readonly]
sso_session = agentops-sso
sso_account_id = <LAB_ACCOUNT_ID>
sso_role_name = AgentOpsReadOnly
region = us-west-2
output = json
```

The placeholders represent private local values. Do not paste or commit the real file because it contains the access portal URL and account IDs.

Official conceptual reference: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso-concepts.html

- [x] **Step 1: Verify AWS CLI v2**

Run:

```bash
aws --version
```

Expected: output begins with `aws-cli/2`.

If AWS CLI is missing or major version is 1, install or update AWS CLI v2 using:

https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

- [x] **Step 2: Retrieve the SSO Start URL and configure the management profile**

Retrieve the exact **AWS access portal URL** saved during Task 2 Step 5. The terms **AWS access portal URL** and **SSO Start URL** refer to the same value in this plan.

If the saved value is unavailable, recover it using either approved route:

1. In the management account and `us-west-2`, open **IAM Identity Center → Dashboard → Settings summary → AWS access portal URL**.
2. From the AWS access portal, open the management account, locate `OrganizationAdmin`, choose **Access keys**, and use the **IAM Identity Center credentials** tab to read **SSO Start URL** and **SSO Region**.

Do not use the temporary OIDC `/authorize` URL that the CLI displays during browser authentication.

Run:

```bash
aws configure sso --profile agentops-org-admin
```

Provide:

- SSO session name: `agentops-sso`
- SSO start URL: the exact private URL retrieved above
- SSO region: `us-west-2`
- Registration scopes: accept the default `sso:account:access`
- Account: management account
- Role: `OrganizationAdmin`
- Default client region: `us-west-2`
- Output format: `json`

When the prompt displays an older default such as **SSO session name [agentops-lab]**, type `agentops-sso` explicitly instead of pressing Enter.

Complete browser authorization as `jorge.nunez`.

After authorization, the wizard must enumerate both assigned AWS accounts. If it reports that only one account is available or automatically selects `OrganizationAdmin` without offering the account list, press **Ctrl+C** and return to Task 7 Step 7.

Select the management account. Because only `OrganizationAdmin` is assigned there, the wizard may select that role automatically; that behavior is correct only for `agentops-org-admin`.

- [x] **Step 3: Configure the bootstrap profile**

Run:

```bash
aws configure sso --profile agentops-lab-bootstrap
```

At **SSO session name**, enter `agentops-sso`. Reuse the existing session values; do not create a second session named after the lab account.

The wizard must offer two accounts. Select `agentops-lab`.

It must then offer both lab roles. Select:

- Role: `AgentOpsBootstrapAdmin`
- Default client region: `us-west-2`
- Output format: `json`

Press **Ctrl+C** if only the management account is offered, `OrganizationAdmin` is selected automatically, `AgentOpsBootstrapAdmin` is absent, or the wizard offers only `AgentOpsReadOnly`. Accepting those values would create a misleading bootstrap profile.

- [x] **Step 4: Configure the read-only profile**

Run:

```bash
aws configure sso --profile agentops-lab-readonly
```

At **SSO session name**, enter the same `agentops-sso` value.

Select:

- Account: `agentops-lab`
- Role: `AgentOpsReadOnly`
- Default client region: `us-west-2`
- Output format: `json`

Press **Ctrl+C** if `agentops-lab` or `AgentOpsReadOnly` is absent, or if the wizard selects `OrganizationAdmin`. Do not accept `AgentOpsBootstrapAdmin` for the read-only profile.

Official reference: https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sso.html

- [x] **Step 5: Log in once and verify all profiles**

Because all three profiles reference the same `agentops-sso` section, one successful browser login establishes the shared IAM Identity Center authentication session. Each STS command then requests temporary credentials for the account and role selected by its profile.

Clear tokens issued before the final account assignments, then authenticate once:

```bash
aws sso logout
aws sso login --profile agentops-org-admin
```

Because all profiles reference `agentops-sso`, browser authentication is shared. Each STS request still obtains credentials for its profile's account and role.

Run this local verification. It compares private identifiers without printing them:

```bash
set -e

ORG_ACCOUNT="$(aws sts get-caller-identity \
  --profile agentops-org-admin \
  --query Account --output text)"
BOOT_ACCOUNT="$(aws sts get-caller-identity \
  --profile agentops-lab-bootstrap \
  --query Account --output text)"
READ_ACCOUNT="$(aws sts get-caller-identity \
  --profile agentops-lab-readonly \
  --query Account --output text)"

ORG_ARN="$(aws sts get-caller-identity \
  --profile agentops-org-admin \
  --query Arn --output text)"
BOOT_ARN="$(aws sts get-caller-identity \
  --profile agentops-lab-bootstrap \
  --query Arn --output text)"
READ_ARN="$(aws sts get-caller-identity \
  --profile agentops-lab-readonly \
  --query Arn --output text)"

test "$ORG_ACCOUNT" != "$BOOT_ACCOUNT"
test "$BOOT_ACCOUNT" = "$READ_ACCOUNT"

case "$ORG_ARN" in *OrganizationAdmin*) ;; *) exit 1 ;; esac
case "$BOOT_ARN" in *AgentOpsBootstrapAdmin*) ;; *) exit 1 ;; esac
case "$READ_ARN" in *AgentOpsReadOnly*) ;; *) exit 1 ;; esac

echo "profile_verification=PASS"
```

Expected: `profile_verification=PASS`.

If STS fails with `ForbiddenException: No access`, compare the profile with Task 7. If the role is absent from the portal, correct the Identity Center assignment. If it launches in the portal, inspect the local `sso_session`, account, and role mapping. Do not create access keys or paste STS output, IDs, or ARNs into chat or GitHub.

- [x] **Step 6: Confirm profile mappings and no static credentials**

First verify the non-sensitive session and role-name mappings:

```bash
aws configure get sso_session --profile agentops-org-admin
aws configure get sso_role_name --profile agentops-org-admin

aws configure get sso_session --profile agentops-lab-bootstrap
aws configure get sso_role_name --profile agentops-lab-bootstrap

aws configure get sso_session --profile agentops-lab-readonly
aws configure get sso_role_name --profile agentops-lab-readonly
```

Expected:

- all three session values are `agentops-sso`;
- the role names are respectively `OrganizationAdmin`, `AgentOpsBootstrapAdmin`, and `AgentOpsReadOnly`.

Then run:

```bash
aws configure list --profile agentops-org-admin
aws configure list --profile agentops-lab-bootstrap
aws configure list --profile agentops-lab-readonly
```

Expected: authentication derives from SSO/session configuration, not a manually entered access key.

Do not print, upload, or commit the contents of AWS credential caches.

- [x] **Step 7: Reconcile accidental Identity Center objects, if present**

Run this step only when an unexpected user or group exists. Do not delete anything until Step 5 prints `profile_verification=PASS` for `jorge.nunez`.

The intended final directory contains exactly these project identities:

```text
Users:
- jorge.nunez

Groups:
- OrganizationAdministrators
- AgentOpsAdministrators
```

A permission set is not a group. Keep the `AgentOpsReadOnly` **permission set** assigned to `AgentOpsAdministrators`; remove only an accidental **group** with that same name.

#### 7.1 Verify the intended access path before cleanup

In **IAM Identity Center → Multi-account permissions → AWS accounts**, open each account and read the **Assigned users and groups** view.

Confirm:

- the management account assigns `OrganizationAdmin` to `OrganizationAdministrators`;
- `agentops-lab` assigns both `AgentOpsBootstrapAdmin` and `AgentOpsReadOnly` to `AgentOpsAdministrators`;
- `jorge.nunez` belongs to both intended groups;
- no intended assignment depends on the accidental user or group.

Stop if any intended role is missing. Repair the group assignment and rerun Step 5 before removing anything.

#### 7.2 Inspect and disable an accidental user

Open **IAM Identity Center → Users → agentops-lab**. Confirm this is the accidental directory user—not the AWS member account—and that its status is **Disabled**.

Review these tabs or sections and record only names and counts privately:

- **Groups**
- **AWS accounts**
- **Applications**
- **MFA devices**
- **Active sessions**

If the user is still enabled, choose **Disable user access**. Do not delete it yet.

For each direct AWS-account assignment shown for this user:

1. Open **Multi-account permissions → AWS accounts**.
2. Select the applicable account.
3. Open **Assigned users and groups**.
4. Select the accidental user—not `jorge.nunez`—and choose **Delete access** or the current equivalent removal action.
5. Confirm that the corresponding assignment for the intended group remains present and successfully provisioned.

If the accidental user belongs to any group, open that group and choose **Remove users from group** for only the accidental user. Remove application assignments as well if any exist.

Official references:

- https://docs.aws.amazon.com/singlesignon/latest/userguide/howtoremoveaccess.html
- https://docs.aws.amazon.com/singlesignon/latest/userguide/removeusersfromgroups.html

#### 7.3 Reverify before deleting the accidental user

Sign out of the AWS access portal, sign back in as `jorge.nunez`, and confirm that the portal still offers:

- management account → `OrganizationAdmin`;
- `agentops-lab` → `AgentOpsBootstrapAdmin`;
- `agentops-lab` → `AgentOpsReadOnly`.

Run Step 5 again and require `profile_verification=PASS`.

Only after explicit human confirmation, zero required assignments, and this successful verification, open **Users → agentops-lab → Delete user** and confirm deletion.

Official reference: https://docs.aws.amazon.com/singlesignon/latest/userguide/deleteusers.html

#### 7.4 Remove an accidental permission-set-named group

Open **IAM Identity Center → Groups → AgentOpsReadOnly** and confirm it is the accidental **group**. Do not open or delete **Permission sets → AgentOpsReadOnly**.

Inspect the group's users, AWS-account assignments, and application assignments. Remove each assignment first:

1. For AWS-account access, use **Multi-account permissions → AWS accounts → Assigned users and groups** and remove only the accidental group.
2. For group membership, use **Groups → AgentOpsReadOnly**, select its users, and choose **Remove users from group**.
3. Remove application assignments if the group has any.

Confirm that `jorge.nunez` remains in `AgentOpsAdministrators` and that both lab permission sets remain assigned to that intended group.

Only after explicit human confirmation and zero remaining dependencies, open **Groups → AgentOpsReadOnly → Delete group** and confirm the exact group name.

Official references:

- https://docs.aws.amazon.com/singlesignon/latest/userguide/users-groups-provisioning.html
- https://docs.aws.amazon.com/singlesignon/latest/userguide/deletegroups.html

#### 7.5 Verify the final inventory and permissions

Refresh **Users** and **Groups** and compare them with the intended inventory at the start of this step.

Then:

1. Sign in to the portal as `jorge.nunez`.
2. Confirm all three intended roles are present.
3. Rerun Step 5 and require `profile_verification=PASS`.
4. Repeat Task 10 Step 2 and require `readonly_write_test=PASS`.

Do not create Task 11 evidence until the accidental user and accidental group are absent and both final tests pass.

If no accidental object exists, mark this step not applicable. Never disable or delete `jorge.nunez`, `OrganizationAdministrators`, `AgentOpsAdministrators`, or any of the three intended permission sets.

### Task 9: Configure consolidated budget and anomaly detection

**Interfaces:**
- Consumes: verified `agentops-org-admin` access and a private alert email.
- Produces: USD 30 consolidated monthly budget, four budget notifications, and one USD 5 anomaly subscription.

Everything in this task belongs to the management account's consolidated billing context. Do not configure it from `agentops-lab`.

- [x] **Step 1: Open Billing from the intended identity and confirm access**

From the AWS access portal, open the management account with `OrganizationAdmin`. Confirm that role in the account menu, then open **Billing and Cost Management**.

Do not enter Billing from either lab role.

Open **Cost Explorer** and choose **Enable Cost Explorer** if needed.

Expected:

- Billing opens without `AccessDenied`;
- Cost Explorer is enabled or already active;
- AWS may report that data needs time to populate.

If Billing remains unavailable, stop and reconfirm Task 1 Step 5. Root-only **Activate IAM Access** and role permissions are separate requirements.

- [x] **Step 2: Create the organization-wide monthly budget**

Open **Billing and Cost Management → Budgets → Create budget**.

Choose **Customize (advanced)** and **Cost budget**.

Configure:

- Budget name: `agentops-monthly-total`
- Period: **Monthly**
- Renewal: **Recurring**
- Budgeting method: **Fixed**
- Monthly amount: **USD 30**
- Cost metric: **Unblended costs**
- Scope: all organization accounts and AWS services

Do not add an account, service, tag, region, or charge-type filter. A filter could hide costs the consolidated safety budget must detect.

Before continuing, confirm the summary represents the whole organization rather than only `agentops-lab`.

Official reference: https://docs.aws.amazon.com/cost-management/latest/userguide/create-cost-budget.html

- [x] **Step 3: Add all four budget notifications**

Choose **Absolute value**, not percentage, when the UI asks for threshold type.

| Basis | Condition | Threshold | Recipient |
|---|---|---:|---|
| Actual cost | Greater than | USD 10 | private alert email |
| Actual cost | Greater than | USD 20 | private alert email |
| Actual cost | Greater than | USD 30 | private alert email |
| Forecasted cost | Greater than | USD 30 | private alert email |

Use the same private address for all four. Do not place it in project documentation or screenshots.

Expected: the budget details show one budget and all four notifications.

Forecast notifications may remain inactive until AWS has enough history; that delay is not a configuration failure.

- [x] **Step 4: Create the organization-wide anomaly monitor**

Open **Billing and Cost Management → Cost Anomaly Detection → Cost monitors → Create monitor**.

Configure:

- Monitor name: `agentops-all-services`
- Monitor type: **AWS services**
- Scope: all AWS services visible to the management account

Do not narrow the monitor to one account or service.

Expected: the monitor exists and is active or awaiting initial cost data.

- [x] **Step 5: Create the anomaly alert subscription**

Open **Cost Anomaly Detection → Alert subscriptions → Create subscription**.

Configure:

- Subscription name: `agentops-cost-anomalies`
- Frequency: **Daily summaries**
- Minimum anomaly impact threshold: **USD 5**
- Recipient: private alert email
- Monitor: `agentops-all-services`

Daily email summaries avoid adding SNS. Immediate individual alerts require SNS and remain out of scope.

Official reference: https://docs.aws.amazon.com/cost-management/latest/userguide/getting-started-ad.html

Expected: the subscription references `agentops-all-services` and displays USD 5.

- [x] **Step 6: Read back the complete cost-control configuration**

Open `agentops-monthly-total` and confirm:

- fixed monthly amount USD 30;
- unblended costs;
- organization-wide scope without narrowing filters;
- actual notifications at USD 10, USD 20, and USD 30;
- forecasted notification at USD 30.

Then confirm:

- monitor `agentops-all-services` exists;
- subscription `agentops-cost-anomalies` uses daily summaries;
- minimum impact is USD 5;
- the private recipient is correct.

Do not wait for cost data or an email. The target is saved configuration, not generated spend.

### Task 10: Verify permissions and account isolation

**Interfaces:**
- Consumes: the three verified CLI profiles and saved cost controls.
- Produces: positive read tests, a negative write test, and evidence that the management account has no AgentOps workloads in `us-west-2`.

- [x] **Step 1: Verify read-only authentication and inventory access**

Run:

```bash
aws s3api list-buckets \
  --profile agentops-lab-readonly

aws eks list-clusters \
  --region us-west-2 \
  --profile agentops-lab-readonly

aws ec2 describe-vpcs \
  --region us-west-2 \
  --profile agentops-lab-readonly
```

Expected:

- all commands authenticate without `ForbiddenException` or `AccessDenied`;
- EKS returns an empty cluster list;
- the default VPC may exist because AWS creates default regional resources automatically;
- a default VPC is not proof that an AgentOps workload was created.

Stop if authentication fails. Do not count a credential or connectivity error as a successful authorization test.

- [x] **Step 2: Prove read-only access cannot create a resource**

This is an intentional negative test. The request must be denied and must not leave a bucket.

Run:

```bash
AGENTOPS_ACCOUNT_ID="$(
  aws sts get-caller-identity \
    --profile agentops-lab-readonly \
    --query Account \
    --output text
)"

AGENTOPS_DENY_TEST_BUCKET="agentops-readonly-deny-${AGENTOPS_ACCOUNT_ID}"

set +e
AGENTOPS_DENY_OUTPUT="$(
  aws s3api create-bucket \
    --bucket "${AGENTOPS_DENY_TEST_BUCKET}" \
    --region us-west-2 \
    --create-bucket-configuration LocationConstraint=us-west-2 \
    --profile agentops-lab-readonly \
    2>&1
)"
AGENTOPS_DENY_STATUS=$?
set -e

if [ "${AGENTOPS_DENY_STATUS}" -eq 0 ]; then
  aws s3api delete-bucket \
    --bucket "${AGENTOPS_DENY_TEST_BUCKET}" \
    --region us-west-2 \
    --profile agentops-lab-bootstrap

  echo "readonly_write_test=FAIL_RESOURCE_WAS_CREATED"
  exit 1
fi

case "${AGENTOPS_DENY_OUTPUT}" in
  *AccessDenied*|*UnauthorizedOperation*)
    echo "readonly_write_test=PASS"
    ;;
  *)
    echo "readonly_write_test=INCONCLUSIVE"
    exit 1
    ;;
esac

unset AGENTOPS_ACCOUNT_ID
unset AGENTOPS_DENY_TEST_BUCKET
unset AGENTOPS_DENY_OUTPUT
unset AGENTOPS_DENY_STATUS
```

Expected: `readonly_write_test=PASS`.

`INCONCLUSIVE` means the command failed for a reason other than authorization. Investigate it; do not count it as least-privilege proof.

If a bucket is unexpectedly created, the script deletes only that exact test bucket with `agentops-lab-bootstrap` and exits. Stop and correct the read-only access path.

- [x] **Step 3: Verify that the management account has no AgentOps workloads**

Run:

```bash
aws eks list-clusters \
  --region us-west-2 \
  --profile agentops-org-admin

aws ec2 describe-instances \
  --region us-west-2 \
  --filters Name=instance-state-name,Values=pending,running,stopping,stopped \
  --query 'Reservations[].Instances[].InstanceId' \
  --output json \
  --profile agentops-org-admin

aws ec2 describe-nat-gateways \
  --region us-west-2 \
  --filter Name=state,Values=pending,available \
  --query 'NatGateways[].NatGatewayId' \
  --output json \
  --profile agentops-org-admin

aws elbv2 describe-load-balancers \
  --region us-west-2 \
  --query 'LoadBalancers[].LoadBalancerArn' \
  --output json \
  --profile agentops-org-admin
```

Expected:

- EKS cluster list is empty;
- EC2 instance IDs are empty;
- NAT gateway IDs are empty;
- load balancer ARNs are empty.

This proves the selected project region. If the management account has hosted workloads elsewhere, repeat the inventory in those regions.

Do not delete unexpected resources. Identify tags, owner, region, creation time, and purpose first.

- [x] **Step 4: Confirm the verification summary**

Continue only when:

- Task 8 printed `profile_verification=PASS`;
- Task 10 Step 1 authenticated successfully;
- Task 10 Step 2 printed `readonly_write_test=PASS`;
- all four management inventories are empty;
- Task 9 cost controls passed their readback.

Record only PASS/FAIL outcomes. Do not copy account IDs, ARNs, emails, URLs, or raw output.

- [x] **Step 5: End cached SSO sessions**

Run:

```bash
aws sso logout
```

Expected: cached Identity Center sessions are removed. The three definitions remain in `~/.aws/config`.

### Task 11: Capture sanitized evidence and commit it

**Files:**
- Create: `docs/evidence/v0.1/aws-account-bootstrap.md`

**Interfaces:**
- Consumes: verified outcomes from Tasks 1–10.
- Produces: public-safe evidence that allows a reviewer to validate the architecture without exposing identifiers.

- [x] **Step 1: Create the evidence document**

Create `docs/evidence/v0.1/aws-account-bootstrap.md` with exactly this structure:

```markdown
# AWS Account Bootstrap Evidence

**Completed:** YYYY-MM-DD
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
```

Replace `YYYY-MM-DD` with the actual date when the verification finishes. Do not reuse the plan creation date unless completion occurred on that date.

Do not mark any item complete unless its corresponding verification passed.

- [x] **Step 2: Scan the evidence for sensitive values**

Run from the repository root:

```bash
rg -n \
  -e '[0-9]{12}' \
  -e 'https://[^ ]*awsapps\\.com' \
  -e 'AKIA[0-9A-Z]{16}' \
  -e 'ASIA[0-9A-Z]{16}' \
  -e 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' \
  -e 'o-[a-z0-9]{10,32}' \
  -e '[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}' \
  -i \
  docs/evidence/v0.1/aws-account-bootstrap.md
```

Expected: no output.

The scan checks account IDs, portal URLs, access keys, private-key headers, organization IDs, and email addresses. It complements review; it does not prove that every possible secret format is absent.

If any match appears, remove or generalize the value and rerun until there is no output.

- [x] **Step 3: Review the exact diff**

Run:

```bash
git diff -- docs/evidence/v0.1/aws-account-bootstrap.md
git status --short
```

Expected: only the intended evidence file is new or modified for this task.

- [x] **Step 4: Commit the evidence**

Run:

```bash
git add docs/evidence/v0.1/aws-account-bootstrap.md
git commit -m "docs: record AWS account bootstrap evidence"
```

Expected: commit succeeds and contains no sensitive data.

- [x] **Step 5: Declare the implementation boundary complete**

The AWS account and identity bootstrap is complete only when every task in this plan is checked.

Do not begin Terraform remote-state implementation in the same change. The next design/implementation boundary is the v0.1 Terraform bootstrap using S3 versioning and native S3 lockfiles.
