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