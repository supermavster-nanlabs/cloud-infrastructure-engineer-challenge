mock_provider "aws" {
  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/mock-function"
    }
  }
}

variables {
  name              = "info-api-info"
  source_dir        = "tests/fixtures/package"
  subnet_ids        = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  security_group_id = "sg-0123456789abcdef0"
  secret_arn        = "arn:aws:secretsmanager:us-east-1:123456789012:secret:rds-mock"
  environment       = { DB_HOST = "db.internal.example" }
}

run "function_runs_inside_the_vpc_with_json_logs" {
  command = plan

  assert {
    condition = (
      aws_lambda_function.this.runtime == "python3.13" &&
      toset(aws_lambda_function.this.vpc_config[0].subnet_ids) == toset(var.subnet_ids) &&
      toset(aws_lambda_function.this.vpc_config[0].security_group_ids) == toset([var.security_group_id]) &&
      aws_lambda_function.this.logging_config[0].log_format == "JSON"
    )
    error_message = "The function must run python3.13 in the given subnets and security group, with JSON logs."
  }
}

run "the_only_extra_permission_is_reading_one_secret" {
  command = plan

  assert {
    condition     = jsondecode(aws_iam_role_policy.read_secret.policy).Statement[0].Resource == var.secret_arn
    error_message = "The function may read exactly the database secret, nothing broader."
  }
}

run "a_missing_package_fails_with_a_clear_message" {
  command = plan

  variables {
    source_dir = "tests/fixtures/not-built"
  }

  expect_failures = [data.archive_file.this]
}
