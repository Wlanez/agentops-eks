mock_provider "aws" {
  override_during = plan

  override_data {
    target = data.aws_availability_zones.available

    values = {
      names = ["us-west-2a", "us-west-2b"]
    }
  }
}


run "two_az_private_eks_network_contract" {
  command = plan

  assert {
    condition     = aws_vpc.dev.cidr_block == "10.20.0.0/16"
    error_message = "The dev VPC must use the approved /16 CIDR."
  }

  assert {
    condition = (
      length(aws_subnet.public) == 2 &&
      length(aws_subnet.private) == 2
    )
    error_message = "The network must create public and private subnets in exactly two Availability Zones."
  }

  assert {
    condition = alltrue([
      for subnet in aws_subnet.private :
      subnet.map_public_ip_on_launch == false
    ])
    error_message = "Private subnets must not assign public IPv4 addresses."
  }

  assert {
    condition     = length(aws_nat_gateway.lab) == 1
    error_message = "The lab topology must create exactly one NAT Gateway."
  }

  assert {
    condition     = aws_vpc_endpoint.s3.service_name == "com.amazonaws.us-west-2.s3"
    error_message = "The network must create the regional S3 Gateway endpoint."
  }
}



run "routing_and_eks_discovery_contract" {
  command = apply

  assert {
    condition     = length(aws_route.private_default) == 2 && alltrue([for route in aws_route.private_default : route.nat_gateway_id == aws_nat_gateway.lab[0].id])
    error_message = "Every private subnet route table must use the single lab NAT Gateway."
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.public : subnet.tags["kubernetes.io/role/elb"] == "1"])
    error_message = "Public subnets must carry the future public load-balancer discovery tag."
  }

  assert {
    condition     = alltrue([for subnet in aws_subnet.private : subnet.tags["kubernetes.io/role/internal-elb"] == "1"])
    error_message = "Private subnets must carry the future internal load-balancer discovery tag."
  }
}
