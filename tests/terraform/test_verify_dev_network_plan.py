import json
import subprocess
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "verify-dev-network-plan.py"

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


def plan(resource_types, actions=None):
    selected_actions = actions or ["create"]
    return {
        "resource_changes": [
            {
                "address": f"{resource_type}.test",
                "mode": "managed",
                "type": resource_type,
                "change": {"actions": selected_actions},
            }
            for resource_type in resource_types
        ]
    }


def expected_resource_types():
    return [
        resource_type
        for resource_type, count in EXPECTED_COUNTS.items()
        for _ in range(count)
    ]


def run_verifier(payload):
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    )


class DevNetworkPlanVerifierTest(unittest.TestCase):
    def test_accepts_exact_create_only_contract(self):
        result = run_verifier(plan(expected_resource_types()))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "dev_network_plan_contract=PASS")

    def test_rejects_added_eks_cluster(self):
        result = run_verifier(plan(expected_resource_types() + ["aws_eks_cluster"]))
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_delete_action(self):
        result = run_verifier(plan(expected_resource_types(), actions=["delete"]))
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_missing_private_route_association(self):
        resource_types = expected_resource_types()
        resource_types.remove("aws_route_table_association")
        result = run_verifier(plan(resource_types))
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
