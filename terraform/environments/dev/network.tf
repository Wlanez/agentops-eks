data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  selected_availability_zones = slice(
    sort(data.aws_availability_zones.available.names),
    0,
    var.availability_zone_count
  )

  availability_zones = {
    for index, availability_zone in local.selected_availability_zones :
    tostring(index) => availability_zone
  }
}

resource "aws_vpc" "dev" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

resource "aws_internet_gateway" "dev" {
  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

resource "aws_subnet" "public" {
  for_each = local.availability_zones

  vpc_id                  = aws_vpc.dev.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, tonumber(each.key))
  map_public_ip_on_launch = true

  tags = {
    Name                     = "${var.project_name}-${var.environment}-public-${each.value}"
    "kubernetes.io/role/elb" = "1"
  }
}

resource "aws_subnet" "private" {
  for_each = local.availability_zones

  vpc_id                  = aws_vpc.dev.id
  availability_zone       = each.value
  cidr_block              = cidrsubnet(var.vpc_cidr, 3, tonumber(each.key) + 2)
  map_public_ip_on_launch = false

  tags = {
    Name                              = "${var.project_name}-${var.environment}-private-${each.value}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-nat"
  }
}

resource "aws_nat_gateway" "lab" {
  count = 1

  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["0"].id

  depends_on = [aws_internet_gateway.dev]

  tags = {
    Name = "${var.project_name}-${var.environment}"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.dev.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"

  route_table_ids = [
    for route_table in aws_route_table.private :
    route_table.id
  ]

  tags = {
    Name = "${var.project_name}-${var.environment}-s3"
  }
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "${var.project_name}-${var.environment}-public"
  }
}

resource "aws_route_table" "private" {
  for_each = local.availability_zones

  vpc_id = aws_vpc.dev.id

  tags = {
    Name = "${var.project_name}-${var.environment}-private-${each.value}"
  }
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.dev.id
}

resource "aws_route" "private_default" {
  for_each = local.availability_zones

  route_table_id         = aws_route_table.private[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.lab[0].id
}

resource "aws_route_table_association" "public" {
  for_each = local.availability_zones

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  for_each = local.availability_zones

  subnet_id      = aws_subnet.private[each.key].id
  route_table_id = aws_route_table.private[each.key].id
}