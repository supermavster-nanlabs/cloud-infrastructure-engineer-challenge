output "identifier" {
  description = "DB instance identifier, as used by the RDS and CloudWatch APIs."
  value       = aws_db_instance.this.identifier
}

output "address" {
  description = "DNS name of the database endpoint. It keeps pointing at the primary after a failover."
  value       = aws_db_instance.this.address
}

output "port" {
  description = "TCP port the database listens on."
  value       = aws_db_instance.this.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = aws_db_instance.this.db_name
}

output "master_secret_arn" {
  description = "Secrets Manager secret holding the master credentials, created and rotated by RDS."
  value       = aws_db_instance.this.master_user_secret[0].secret_arn
}

output "details" {
  description = "Facts about the instance that the function reports. They are Terraform's view, not a live lookup."
  value = {
    class                 = aws_db_instance.this.instance_class
    multi_az              = aws_db_instance.this.multi_az
    availability_zone     = aws_db_instance.this.availability_zone
    backup_retention_days = aws_db_instance.this.backup_retention_period
  }
}
