output "backend_contract" {
  description = "Non-sensitive proof that dev uses the approved backend contract."
  value       = terraform_data.backend_contract.output
}