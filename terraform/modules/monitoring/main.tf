locals {
  alarms = {
    "rds-cpu-high" = {
      description         = "Database CPU above 80% for 15 minutes"
      namespace           = "AWS/RDS"
      metric_name         = "CPUUtilization"
      dimensions          = { DBInstanceIdentifier = var.db_instance_identifier }
      statistic           = "Average"
      period              = 300
      evaluation_periods  = 3
      threshold           = 80
      comparison_operator = "GreaterThanThreshold"
    }
    "lambda-errors" = {
      description         = "The function returned an error"
      namespace           = "AWS/Lambda"
      metric_name         = "Errors"
      dimensions          = { FunctionName = var.lambda_function_name }
      statistic           = "Sum"
      period              = 300
      evaluation_periods  = 1
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
    }
    # A database that cannot be reached is a handled 503, not a function error,
    # so this is the alarm that catches it.
    "api-5xx" = {
      description         = "The API returned a server error"
      namespace           = "AWS/ApiGateway"
      metric_name         = "5xx"
      dimensions          = { ApiId = var.api_id }
      statistic           = "Sum"
      period              = 300
      evaluation_periods  = 1
      threshold           = 1
      comparison_operator = "GreaterThanOrEqualToThreshold"
    }
  }
}

resource "aws_sns_topic" "alerts" {
  # checkov:skip=CKV_AWS_26: CloudWatch alarms cannot publish to a topic using the AWS-managed SNS key, and a custom key is not worth it here
  name = "${var.name}-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  for_each = var.alert_email == null ? toset([]) : toset([var.alert_email])

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${var.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric_name
  dimensions          = each.value.dimensions
  statistic           = each.value.statistic
  period              = each.value.period
  evaluation_periods  = each.value.evaluation_periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison_operator

  # A quiet system emits no data points; that is not a failure.
  treat_missing_data = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}
