output "aws_account_id" {
  description = "AWS account that owns the dev environment."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "AWS region for the dev environment."
  value       = var.aws_region
}

output "cluster_name" {
  description = "Amazon EKS cluster name."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "Amazon EKS Kubernetes API endpoint."
  value       = aws_eks_cluster.main.endpoint
}

output "node_group_name" {
  description = "Managed EKS node group name."
  value       = aws_eks_node_group.general.node_group_name
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs."
  value       = values(aws_subnet.public)[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by EKS workers."
  value       = values(aws_subnet.private)[*].id
}

output "ecr_repository_url" {
  description = "ECR repository URL for the future demo API image."
  value       = aws_ecr_repository.demo_api.repository_url
}

output "core_addon_versions" {
  description = "Resolved versions of the managed EKS core add-ons."
  value = {
    for name, addon in aws_eks_addon.core : name => addon.addon_version
  }
}

output "update_kubeconfig_command" {
  description = "Command used to configure kubectl for this cluster."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region ${var.aws_region}"
}
