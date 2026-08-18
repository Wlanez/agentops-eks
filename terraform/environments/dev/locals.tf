locals {
  name_prefix = "${var.project_name}-${var.environment}"
  cluster_name = local.name_prefix

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnet_cidrs = {
    for index, az in local.azs : az => cidrsubnet(var.vpc_cidr, 4, index)
  }

  private_subnet_cidrs = {
    for index, az in local.azs : az => cidrsubnet(var.vpc_cidr, 4, index + 8)
  }

  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}
