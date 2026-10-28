resource "terraform_data" "backend_contract" {
  input = {
    project     = "agentops-eks"
    environment = "dev"
    backend     = "s3"
    locking     = "native-s3-lockfile"
  }
}