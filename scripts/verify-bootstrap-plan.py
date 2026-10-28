#!/usr/bin/env python3
import json
import sys

EXPECTED_TYPES = {
    "aws_s3_bucket",
    "aws_s3_bucket_ownership_controls",
    "aws_s3_bucket_public_access_block",
    "aws_s3_bucket_versioning",
    "aws_s3_bucket_server_side_encryption_configuration",
    "aws_s3_bucket_policy",
}


def fail(reason):
    print(f"bootstrap_plan_contract=FAIL_{reason}", file=sys.stderr)
    raise SystemExit(1)


try:
    plan = json.load(sys.stdin)
except (json.JSONDecodeError, UnicodeDecodeError):
    fail("INVALID_JSON")

changes = []

for item in plan.get("resource_changes", []):
    if item.get("mode") != "managed":
        continue

    actions = item.get("change", {}).get("actions", [])
    if actions == ["no-op"]:
        continue

    changes.append((item.get("type"), actions))

actual_types = {resource_type for resource_type, _ in changes}

if len(changes) != len(EXPECTED_TYPES):
    fail("UNEXPECTED_RESOURCE_COUNT")

if actual_types != EXPECTED_TYPES:
    fail("UNEXPECTED_RESOURCE_TYPE")

if any(actions != ["create"] for _, actions in changes):
    fail("NON_CREATE_ACTION")

print("bootstrap_plan_contract=PASS")