output "topic_arn" {
  description = "SNS topic that receives every alarm and recovery."
  value       = aws_sns_topic.alerts.arn
}
