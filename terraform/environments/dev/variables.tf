variable "aws_region" {
  description = "AWS region for the dev environment."
  type        = string
  default     = "us-west-2"
}

variable "project_name" {
  description = "Stable project prefix used in AWS resource names and tags."
  type        = string
  default     = "agentops-eks"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "project_name must contain only lowercase letters, numbers, and hyphens."
  }
}

variable "environment" {
  description = "Environment name."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR for the lab VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "kubernetes_version" {
  description = "Amazon EKS Kubernetes minor version. Keep this on a version supported by EKS."
  type        = string
  default     = "1.36"
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Use your current public IP as a /32 for the lab."
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0
    error_message = "Provide at least one CIDR allowed to access the public EKS API endpoint."
  }
}

variable "node_instance_types" {
  description = "EC2 instance types used by the managed node group."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "node_desired_size" {
  description = "Desired number of managed worker nodes for the lab."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of managed worker nodes."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Maximum number of managed worker nodes."
  type        = number
  default     = 3
}
