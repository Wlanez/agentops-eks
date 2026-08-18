terraform {
  backend "s3" {
    key          = "agentops-eks/dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
