#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/aws-terraform-preflight.sh"
FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN"' EXIT

cat > "$FAKE_BIN/aws" <<'FAKE_AWS'
#!/usr/bin/env bash
set -euo pipefail

if [ "${MOCK_AUTH_FAIL:-0}" = "1" ]; then
  exit 1
fi

if [ "$1" = "sts" ] && [ "$2" = "get-caller-identity" ]; then
  shift 2
  profile=""
  query=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --profile) profile="$2"; shift 2 ;;
      --query) query="$2"; shift 2 ;;
      --output) shift 2 ;;
      *) shift ;;
    esac
  done

  if [ "$profile" = "agentops-lab-bootstrap" ]; then
    case "$query" in
      Account) printf '%s\n' "${MOCK_LAB_ACCOUNT:-LAB}" ;;
      Arn) printf '%s\n' "${MOCK_LAB_ARN:-arn:aws:sts::LAB:assumed-role/AgentOpsBootstrapAdmin/session}" ;;
      *) exit 2 ;;
    esac
    exit 0
  fi

  if [ "$profile" = "agentops-org-admin" ] && [ "$query" = "Account" ]; then
    printf '%s\n' "${MOCK_ORG_ACCOUNT:-ORG}"
    exit 0
  fi

  exit 2
fi

if [ "$1" = "configure" ] &&
   [ "$2" = "get" ] &&
   [ "$3" = "region" ] &&
   [ "$4" = "--profile" ] &&
   [ "$5" = "agentops-lab-bootstrap" ]; then
  printf '%s\n' "${MOCK_REGION:-us-west-2}"
  exit 0
fi

exit 2
FAKE_AWS

chmod +x "$FAKE_BIN/aws"

invoke_preflight() {
  (
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_SESSION_TOKEN
    unset AWS_SECURITY_TOKEN
    export PATH="$FAKE_BIN:$PATH"

    while [ "$#" -gt 0 ]; do
      export "$1"
      shift
    done

    bash "$SCRIPT"
  )
}

expect_pass() {
  name="$1"
  shift
  output="$(invoke_preflight "$@")"
  test "$output" = "aws_terraform_preflight=PASS"
  printf 'PASS: %s\n' "$name"
}

expect_fail() {
  name="$1"
  shift

  if invoke_preflight "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s unexpectedly passed\n' "$name" >&2
    exit 1
  fi

  printf 'PASS: %s\n' "$name"
}

expect_pass "valid lab identity"
expect_fail "static credential variable" "AWS_ACCESS_KEY_ID=fixture"
expect_fail "wrong role" "MOCK_LAB_ARN=arn:aws:sts::LAB:assumed-role/OrganizationAdmin/session"
expect_fail "management and lab are equal" "MOCK_ORG_ACCOUNT=LAB"
expect_fail "wrong region" "MOCK_REGION=us-east-1"
expect_fail "authentication failure" "MOCK_AUTH_FAIL=1"

echo "preflight_tests=PASS"