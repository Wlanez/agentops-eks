variable "aws_region" {
  description = "AWS region that stores the Terraform state bucket."
  type        = string
  default     = "us-west-2"
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "agentops-eks"
      Environment = "bootstrap"
      ManagedBy   = "Terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}
