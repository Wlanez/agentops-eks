locals {
  core_eks_addons = toset([
    "vpc-cni",
    "kube-proxy",
    "coredns",
  ])
}

resource "aws_security_group" "eks_control_plane" {
  name        = "${local.name_prefix}-eks-control-plane"
  description = "Additional security group attached to the EKS control-plane ENIs."
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-eks-control-plane"
  }
}

resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.kubernetes_version

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = values(aws_subnet.private)[*].id
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.cluster_endpoint_public_access_cidrs
    security_group_ids      = [aws_security_group.eks_control_plane.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
  ]

  tags = {
    Name = local.cluster_name
  }
}

resource "aws_eks_node_group" "general" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-general"
  node_role_arn   = aws_iam_role.eks_nodes.arn
  subnet_ids      = values(aws_subnet.private)[*].id
  version         = var.kubernetes_version
  instance_types  = var.node_instance_types
  capacity_type   = "ON_DEMAND"

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node,
    aws_iam_role_policy_attachment.ecr_pull_only,
    aws_iam_role_policy_attachment.eks_cni_lab,
  ]

  tags = {
    Name = "${local.name_prefix}-general"
  }
}

data "aws_eks_addon_version" "core" {
  for_each = local.core_eks_addons

  addon_name         = each.value
  kubernetes_version = aws_eks_cluster.main.version
  most_recent        = true
}

resource "aws_eks_addon" "core" {
  for_each = local.core_eks_addons

  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = each.value
  addon_version               = data.aws_eks_addon_version.core[each.key].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"

  depends_on = [aws_eks_node_group.general]
}
