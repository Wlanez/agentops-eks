#!/usr/bin/env python3

from collections import Counter
import json
import sys


EXPECTED_COUNTS = {
    "aws_vpc": 1,
    "aws_internet_gateway": 1,
    "aws_subnet": 4,
    "aws_route_table": 3,
    "aws_route": 3,
    "aws_route_table_association": 4,
    "aws_eip": 1,
    "aws_nat_gateway": 1,
    "aws_vpc_endpoint": 1,
}


def fail(reason):
    print(f"dev_network_plan_contract=FAIL_{reason}", file=sys.stderr)
    raise SystemExit(1)


try:
    plan = json.load(sys.stdin)
except (json.JSONDecodeError, UnicodeDecodeError):
    fail("INVALID_JSON")

if not isinstance(plan, dict):
    fail("INVALID_PLAN")

resource_types = []

for item in plan.get("resource_changes", []):
    if item.get("mode") != "managed":
        continue

    actions = item.get("change", {}).get("actions", [])
    if actions == ["no-op"]:
        continue
    if actions != ["create"]:
        fail("NON_CREATE_ACTION")
    resource_types.append(item.get("type"))

if Counter(resource_types) != Counter(EXPECTED_COUNTS):
    fail("UNEXPECTED_RESOURCE_GRAPH")

print("dev_network_plan_contract=PASS")
