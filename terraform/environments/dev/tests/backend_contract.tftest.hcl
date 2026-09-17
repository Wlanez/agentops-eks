mock_provider "aws" {
  override_during = plan

  override_data {
    target = data.aws_availability_zones.available

    values = {
      names = ["us-west-2a", "us-west-2b"]
    }
  }
}

run "backend_contract" {
  command = plan

  assert {
    condition     = terraform_data.backend_contract.input.project == "agentops-eks"
    error_message = "The contract must identify agentops-eks."
  }

  assert {
    condition     = terraform_data.backend_contract.input.environment == "dev"
    error_message = "The contract must identify dev."
  }

  assert {
    condition     = terraform_data.backend_contract.input.backend == "s3"
    error_message = "The contract must identify S3."
  }

  assert {
    condition     = terraform_data.backend_contract.input.locking == "native-s3-lockfile"
    error_message = "The contract must identify native S3 locking."
  }
}