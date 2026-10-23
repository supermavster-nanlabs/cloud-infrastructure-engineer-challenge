output "vpc_id" {
  description = "ID of the VPC."
  value       = aws_vpc.this.id
}

output "app_subnet_ids" {
  description = "Private subnets for the Lambda, ordered by availability zone."
  value       = [for az in local.azs : aws_subnet.app[az].id]
}

output "data_subnet_ids" {
  description = "Isolated subnets for the database, ordered by availability zone."
  value       = [for az in local.azs : aws_subnet.data[az].id]
}

output "lambda_security_group_id" {
  description = "Security group for the Lambda function."
  value       = aws_security_group.lambda.id
}

output "database_security_group_id" {
  description = "Security group for the database."
  value       = aws_security_group.database.id
}

output "nat_public_ips" {
  description = "Public IPs of the NAT gateways."
  value       = [for eip in aws_eip.nat : eip.public_ip]
}
