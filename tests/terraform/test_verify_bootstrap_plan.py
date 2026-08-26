import json
import subprocess
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = REPO_ROOT / "scripts" / "verify-bootstrap-plan.py"

ALLOWED_TYPES = [
    "aws_s3_bucket",
    "aws_s3_bucket_ownership_controls",
    "aws_s3_bucket_public_access_block",
    "aws_s3_bucket_versioning",
    "aws_s3_bucket_server_side_encryption_configuration",
    "aws_s3_bucket_policy",
]


def plan(resource_types, actions=None):
    selected_actions = actions or ["create"]
    return {
        "resource_changes": [
            {
                "address": f"{resource_type}.state",
                "mode": "managed",
                "type": resource_type,
                "change": {"actions": selected_actions},
            }
            for resource_type in resource_types
        ]
    }


def run_verifier(payload):
    return subprocess.run(
        [sys.executable, str(SCRIPT)],
        input=json.dumps(payload),
        text=True,
        capture_output=True,
        check=False,
    )


class BootstrapPlanVerifierTest(unittest.TestCase):
    def test_accepts_exact_create_only_contract(self):
        result = run_verifier(plan(ALLOWED_TYPES))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "bootstrap_plan_contract=PASS")

    def test_rejects_unexpected_resource(self):
        result = run_verifier(plan(ALLOWED_TYPES + ["aws_dynamodb_table"]))
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_destroy_action(self):
        result = run_verifier(plan(ALLOWED_TYPES, ["delete"]))
        self.assertNotEqual(result.returncode, 0)

    def test_rejects_missing_resource(self):
        result = run_verifier(plan(ALLOWED_TYPES[:-1]))
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()