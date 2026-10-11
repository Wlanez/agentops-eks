variable "aws_region" {
  description = "AWS region approved for the AgentOps lab."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.aws_region == "us-west-2"
    error_message = "The approved AgentOps region is us-west-2."
  }
}

variable "project_name" {
  description = "Project name used for resource tags."
  type        = string
  default     = "agentops-eks"
}

variable "environment" {
  description = "Deployment environment."
  type        = string
  default     = "dev"
}

variable "vpc_cidr" {
  description = "IPv4 CIDR assigned to the dev VPC."
  type        = string
  default     = "10.20.0.0/16"

  validation {
    condition     = var.vpc_cidr == "10.20.0.0/16"
    error_message = "The approved dev VPC CIDR is 10.20.0.0/16."
  }
}

variable "availability_zone_count" {
  description = "Number of Availability Zones used by the dev network."
  type        = number
  default     = 2

  validation {
    condition     = var.availability_zone_count == 2
    error_message = "The v0.1 network requires exactly two Availability Zones."
  }
}