output "function_name" {
  description = "Name of the function."
  value       = aws_lambda_function.this.function_name
}

output "invoke_arn" {
  description = "ARN API Gateway uses to invoke the function."
  value       = aws_lambda_function.this.invoke_arn
}

output "log_group_name" {
  description = "CloudWatch log group the function writes to."
  value       = aws_cloudwatch_log_group.this.name
}
