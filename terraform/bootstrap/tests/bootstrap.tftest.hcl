mock_provider "aws" {}

run "protected_state_bucket_contract" {
  command = plan

  variables {
    aws_region   = "us-west-2"
    project_name = "agentops-eks"
  }

  assert {
    condition     = aws_s3_bucket.state.bucket_prefix == "agentops-eks-tfstate-"
    error_message = "The bucket must use the private generated-name prefix."
  }

  assert {
    condition     = aws_s3_bucket.state.force_destroy == false
    error_message = "The state bucket must reject force deletion."
  }

  assert {
    condition     = aws_s3_bucket_versioning.state.versioning_configuration[0].status == "Enabled"
    error_message = "State versioning must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_server_side_encryption_configuration.state.rule[0].apply_server_side_encryption_by_default[0].sse_algorithm == "AES256"
    error_message = "State encryption must use explicit SSE-S3."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.state.block_public_acls,
      aws_s3_bucket_public_access_block.state.block_public_policy,
      aws_s3_bucket_public_access_block.state.ignore_public_acls,
      aws_s3_bucket_public_access_block.state.restrict_public_buckets
    ])
    error_message = "All four S3 public-access blocks must be enabled."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.state.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs must be disabled with Bucket Owner Enforced."
  }
}

run "reject_wrong_region" {
  command = plan

  variables {
    aws_region = "us-east-1"
  }

  expect_failures = [var.aws_region]
}