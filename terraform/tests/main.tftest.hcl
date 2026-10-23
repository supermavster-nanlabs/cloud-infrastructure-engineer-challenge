# Applies the whole stack against a mocked AWS provider, as a first real apply
# would. It catches wiring mistakes that module tests cannot, such as a
# for_each keyed by an ID that only exists after apply.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/mock"
    }
  }

  mock_resource "aws_db_instance" {
    defaults = {
      identifier        = "info-api-db"
      availability_zone = "us-east-1a"
      master_user_secret = [{
        secret_arn    = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-mock"
        kms_key_id    = "arn:aws:kms:us-east-1:123456789012:key/11111111-1111-1111-1111-111111111111"
        secret_status = "active"
      }]
    }
  }

  mock_resource "aws_lambda_function" {
    defaults = {
      invoke_arn = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:mock/invocations"
    }
  }

  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      id            = "abc123defg"
      api_endpoint  = "https://abc123defg.execute-api.us-east-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:abc123defg"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:mock-alerts"
    }
  }
}

variables {
  lambda_package_dir = "modules/lambda/tests/fixtures/package"
}

run "the_default_stack_applies_and_publishes_the_endpoint" {
  command = apply

  assert {
    condition     = output.info_url == "https://abc123defg.execute-api.us-east-1.amazonaws.com/info"
    error_message = "The published URL must be the API endpoint plus /info."
  }

  assert {
    condition     = output.lambda_function_name == "info-api-info" && length(output.nat_public_ips) == 1
    error_message = "Expected the function named after the project and one shared NAT gateway."
  }
}

run "one_nat_gateway_per_zone_reaches_the_root" {
  command = apply

  variables {
    az_count           = 3
    nat_gateway_per_az = true
  }

  assert {
    condition     = length(output.nat_public_ips) == 3
    error_message = "nat_gateway_per_az and az_count must reach the network module."
  }
}
