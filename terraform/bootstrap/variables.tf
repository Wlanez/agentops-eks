variable "aws_region" {
  description = "AWS region that stores the AgentOps Terraform backend."
  type        = string
  default     = "us-west-2"

  validation {
    condition     = var.aws_region == "us-west-2"
    error_message = "The approved AgentOps region is us-west-2."
  }
}

variable "project_name" {
  description = "Stable lowercase project identifier used in names and tags."
  type        = string
  default     = "agentops-eks"

  validation {
    condition = (
      length(var.project_name) >= 3 &&
      length(var.project_name) <= 30 &&
      can(regex("^[a-z0-9-]+$", var.project_name))
    )
    error_message = "project_name must contain 3-30 lowercase letters, numbers, or hyphens."
  }
}