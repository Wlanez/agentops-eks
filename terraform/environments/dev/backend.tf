terraform {
  backend "s3" {
    key          = "environments/dev/terraform.tfstate"
    region       = "us-west-2"
    encrypt      = true
    use_lockfile = true
  }
}