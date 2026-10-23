mock_provider "aws" {
  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:info-api-alerts"
    }
  }
}

variables {
  name                   = "info-api"
  db_instance_identifier = "info-api-db"
  lambda_function_name   = "info-api-info"
  api_id                 = "abc123defg"
}

run "alarms_watch_the_database_the_function_and_the_api" {
  command = plan

  assert {
    condition = (
      toset(keys(aws_cloudwatch_metric_alarm.this)) == toset(["rds-cpu-high", "lambda-errors", "api-5xx"]) &&
      aws_cloudwatch_metric_alarm.this["rds-cpu-high"].dimensions["DBInstanceIdentifier"] == "info-api-db" &&
      aws_cloudwatch_metric_alarm.this["lambda-errors"].dimensions["FunctionName"] == "info-api-info" &&
      aws_cloudwatch_metric_alarm.this["api-5xx"].dimensions["ApiId"] == "abc123defg"
    )
    error_message = "Expected a database, a function and an API alarm, each on the right resource."
  }
}

run "every_alarm_notifies_on_alarm_and_recovery" {
  command = apply

  assert {
    condition = alltrue([
      for alarm in aws_cloudwatch_metric_alarm.this :
      alarm.alarm_actions == toset([aws_sns_topic.alerts.arn]) &&
      alarm.ok_actions == toset([aws_sns_topic.alerts.arn]) &&
      alarm.treat_missing_data == "notBreaching"
    ])
    error_message = "Alarms and recoveries must go to the topic, and missing data must not count as a breach."
  }
}

run "an_email_is_optional" {
  command = plan

  assert {
    condition     = length(aws_sns_topic_subscription.email) == 0
    error_message = "Without alert_email there must be no subscription."
  }
}
