#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/verify-state-bucket.sh"
FAKE_BIN="$(mktemp -d)"
trap 'rm -rf "$FAKE_BIN"' EXIT

cat > "$FAKE_BIN/aws" <<'FAKE_AWS'
#!/usr/bin/env bash
set -euo pipefail

case " $* " in
  *" get-bucket-location "*) printf '%s\n' "${MOCK_REGION:-us-west-2}" ;;
  *" get-bucket-versioning "*) printf '%s\n' "${MOCK_VERSIONING:-Enabled}" ;;
  *" get-bucket-encryption "*) printf '%s\n' "${MOCK_ENCRYPTION:-AES256}" ;;
  *" get-public-access-block "*) printf '%s\n' "${MOCK_PUBLIC_BLOCK:-true}" ;;
  *" get-bucket-ownership-controls "*) printf '%s\n' "${MOCK_OWNERSHIP:-BucketOwnerEnforced}" ;;
  *" get-bucket-policy "*)
    if [ "${MOCK_TLS_POLICY:-valid}" = "valid" ]; then
      printf '%s\n' '{"Version":"2012-10-17","Statement":[{"Sid":"DenyInsecureTransport","Effect":"Deny","Action":"s3:*","Resource":["bucket","bucket/*"],"Condition":{"Bool":{"aws:SecureTransport":"false"}}}]}'
    else
      printf '%s\n' '{"Version":"2012-10-17","Statement":[]}'
    fi
    ;;
  *" get-bucket-tagging "*) printf '%s\n' "${MOCK_TAG_COUNT:-1}" ;;
  *) exit 2 ;;
esac
FAKE_AWS

chmod +x "$FAKE_BIN/aws"

invoke_readback() {
  (
    export PATH="$FAKE_BIN:$PATH"
    export STATE_BUCKET_NAME="agentops-eks-tfstate-fixture"

    while [ "$#" -gt 0 ]; do
      export "$1"
      shift
    done

    bash "$SCRIPT"
  )
}

expect_pass() {
  output="$(invoke_readback)"
  test "$output" = "state_bucket_readback=PASS"
  echo "PASS: valid bucket controls"
}

expect_fail() {
  name="$1"
  shift

  if invoke_readback "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s unexpectedly passed\n' "$name" >&2
    exit 1
  fi

  printf 'PASS: %s\n' "$name"
}

expect_pass
expect_fail "wrong region" "MOCK_REGION=us-east-1"
expect_fail "versioning disabled" "MOCK_VERSIONING=Suspended"
expect_fail "wrong encryption" "MOCK_ENCRYPTION=aws:kms"
expect_fail "public access not blocked" "MOCK_PUBLIC_BLOCK=false"
expect_fail "ACL ownership enabled" "MOCK_OWNERSHIP=ObjectWriter"
expect_fail "missing TLS deny" "MOCK_TLS_POLICY=invalid"
expect_fail "missing tags" "MOCK_TAG_COUNT=0"

echo "state_bucket_readback_tests=PASS"