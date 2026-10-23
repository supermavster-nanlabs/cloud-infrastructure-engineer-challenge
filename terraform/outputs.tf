output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "nat_public_ips" {
  description = "Public IPs the private subnets' outbound traffic comes from."
  value       = module.network.nat_public_ips
}

output "lambda_function_name" {
  description = "Name of the Lambda function."
  value       = module.lambda.function_name
}

output "lambda_log_group_name" {
  description = "CloudWatch log group the Lambda writes to."
  value       = module.lambda.log_group_name
}
