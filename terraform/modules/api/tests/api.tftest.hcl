mock_provider "aws" {
  mock_resource "aws_apigatewayv2_api" {
    defaults = {
      id            = "abc123defg"
      api_endpoint  = "https://abc123defg.execute-api.us-east-1.amazonaws.com"
      execution_arn = "arn:aws:execute-api:us-east-1:123456789012:abc123defg"
    }
  }

  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/aws/apigateway/info-api-info/access"
    }
  }
}

variables {
  name                   = "info-api-info"
  lambda_function_name   = "info-api-info"
  lambda_invoke_arn      = "arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:123456789012:function:info-api-info/invocations"
  integration_timeout_ms = 16000
}

run "one_get_route_proxies_to_the_lambda" {
  command = plan

  assert {
    condition = (
      aws_apigatewayv2_route.this.route_key == "GET /info" &&
      aws_apigatewayv2_integration.this.integration_type == "AWS_PROXY" &&
      aws_apigatewayv2_integration.this.timeout_milliseconds == 16000
    )
    error_message = "The only route must be GET /info, proxied to the Lambda."
  }
}

run "only_that_route_may_invoke_the_function" {
  command = apply

  assert {
    condition = (
      aws_lambda_permission.invoke.principal == "apigateway.amazonaws.com" &&
      endswith(aws_lambda_permission.invoke.source_arn, "/*/GET/info")
    )
    error_message = "The invoke permission must be limited to the GET /info route."
  }

  assert {
    condition     = output.route_url == "https://abc123defg.execute-api.us-east-1.amazonaws.com/info"
    error_message = "route_url must be the API endpoint plus the route path."
  }
}

run "rejects_a_catch_all_route" {
  command = plan

  variables {
    route_key = "ANY /{proxy+}"
  }

  expect_failures = [var.route_key]
}
