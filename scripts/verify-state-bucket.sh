#!/usr/bin/env bash
set -euo pipefail

PROFILE="${AGENTOPS_LAB_PROFILE:-agentops-lab-bootstrap}"
EXPECTED_REGION="${AGENTOPS_REGION:-us-west-2}"
BUCKET="${STATE_BUCKET_NAME:-}"

fail() {
  printf 'state_bucket_readback=FAIL_%s\n' "$1" >&2
  exit 1
}

case "$BUCKET" in
  agentops-eks-tfstate-*) ;;
  *) fail "UNEXPECTED_BUCKET_NAME" ;;
esac

REGION="$(aws s3api get-bucket-location \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query LocationConstraint --output text 2>/dev/null)" ||
  fail "REGION_READ"

[ "$REGION" = "$EXPECTED_REGION" ] || fail "REGION"

VERSIONING="$(aws s3api get-bucket-versioning \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query Status --output text 2>/dev/null)" ||
  fail "VERSIONING_READ"

[ "$VERSIONING" = "Enabled" ] || fail "VERSIONING"

ENCRYPTION="$(aws s3api get-bucket-encryption \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query 'ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm' \
  --output text 2>/dev/null)" ||
  fail "ENCRYPTION_READ"

[ "$ENCRYPTION" = "AES256" ] || fail "ENCRYPTION"

for setting in \
  BlockPublicAcls \
  BlockPublicPolicy \
  IgnorePublicAcls \
  RestrictPublicBuckets
do
  value="$(aws s3api get-public-access-block \
    --bucket "$BUCKET" --profile "$PROFILE" \
    --query "PublicAccessBlockConfiguration.$setting" \
    --output text 2>/dev/null)" ||
    fail "PUBLIC_ACCESS_READ"

  case "$value" in
    true|True) ;;
    *) fail "PUBLIC_ACCESS" ;;
  esac
done

OWNERSHIP="$(aws s3api get-bucket-ownership-controls \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query 'OwnershipControls.Rules[0].ObjectOwnership' \
  --output text 2>/dev/null)" ||
  fail "OWNERSHIP_READ"

[ "$OWNERSHIP" = "BucketOwnerEnforced" ] || fail "OWNERSHIP"

POLICY="$(aws s3api get-bucket-policy \
  --bucket "$BUCKET" --profile "$PROFILE" \
  --query Policy --output text 2>/dev/null)" ||
  fail "POLICY_READ"

if ! printf '%s' "$POLICY" | python3 -c '
import json
import sys

policy = json.load(sys.stdin)
valid = any(
    statement.get("Effect") == "Deny"
    and statement.get("Condition", {})
        .get("Bool", {})
        .get("aws:SecureTransport") == "false"
    for statement in policy.get("Statement", [])
)
raise SystemExit(0 if valid else 1)
'; then
  fail "TLS_POLICY"
fi

for pair in \
  "Project=agentops-eks" \
  "Environment=bootstrap" \
  "ManagedBy=Terraform" \
  "Purpose=RemoteState"
do
  key="${pair%%=*}"
  expected="${pair#*=}"

  count="$(aws s3api get-bucket-tagging \
    --bucket "$BUCKET" --profile "$PROFILE" \
    --query "length(TagSet[?Key=='$key' && Value=='$expected'])" \
    --output text 2>/dev/null)" ||
    fail "TAG_READ"

  [ "$count" = "1" ] || fail "TAG"
done

unset REGION VERSIONING ENCRYPTION OWNERSHIP POLICY
unset value pair key expected count
echo "state_bucket_readback=PASS"