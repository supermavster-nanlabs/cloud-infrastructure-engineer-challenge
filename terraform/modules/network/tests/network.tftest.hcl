mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }
}

variables {
  name               = "info-api"
  cidr_block         = "10.20.0.0/16"
  az_count           = 2
  nat_gateway_per_az = false
}

run "each_tier_has_its_own_subnets" {
  command = plan

  assert {
    condition = (
      [for az in ["us-east-1a", "us-east-1b"] : aws_subnet.public[az].cidr_block] == ["10.20.0.0/24", "10.20.1.0/24"] &&
      [for az in ["us-east-1a", "us-east-1b"] : aws_subnet.app[az].cidr_block] == ["10.20.10.0/24", "10.20.11.0/24"] &&
      [for az in ["us-east-1a", "us-east-1b"] : aws_subnet.data[az].cidr_block] == ["10.20.20.0/24", "10.20.21.0/24"]
    )
    error_message = "Public, app and data subnets must follow the 0, 10 and 20 offsets."
  }
}

run "one_shared_nat_gateway_by_default" {
  command = plan

  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_route.app_nat) == 2
    error_message = "Expected one NAT gateway, with a default route from each app subnet."
  }
}

run "nat_gateway_per_zone_when_asked" {
  command = plan

  variables {
    nat_gateway_per_az = true
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 2
    error_message = "Expected one NAT gateway per zone."
  }
}

run "database_accepts_only_the_lambda_security_group" {
  command = apply

  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.database_from_lambda.referenced_security_group_id == aws_security_group.lambda.id &&
      aws_vpc_security_group_ingress_rule.database_from_lambda.cidr_ipv4 == null &&
      aws_vpc_security_group_ingress_rule.database_from_lambda.from_port == 5432
    )
    error_message = "The database must accept TCP 5432 from the Lambda security group only, never from a CIDR range."
  }
}

run "rejects_a_single_zone" {
  command = plan

  variables {
    az_count = 1
  }

  expect_failures = [var.az_count]
}
