locals {
  identifier = "${var.name}-db"
}

resource "aws_db_subnet_group" "this" {
  name       = local.identifier
  subnet_ids = var.subnet_ids
}

# TLS is required explicitly rather than relying on the engine default.
resource "aws_db_parameter_group" "this" {
  # checkov:skip=CKV2_AWS_30: database logs are not exported, so query logging would go nowhere; see docs/decisions.md
  name   = "${local.identifier}-pg${var.postgres_major_version}"
  family = "postgres${var.postgres_major_version}"

  # RDS reports this parameter as pending-reboot; declaring "immediate" shows a diff on every plan.
  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "this" {
  # checkov:skip=CKV_AWS_118: enhanced monitoring is not enabled; CloudWatch metrics cover this workload
  # checkov:skip=CKV_AWS_129: database logs are not exported, to keep the stack small; see docs/decisions.md
  # checkov:skip=CKV_AWS_157: multi_az is a setting, off by default to keep a test deployment cheap
  # checkov:skip=CKV_AWS_293: off by default so a test deployment can be destroyed; turn it on in production
  # checkov:skip=CKV_AWS_353: Performance Insights is not enabled
  # checkov:skip=CKV_AWS_354: Performance Insights is not enabled
  identifier     = local.identifier
  engine         = "postgres"
  engine_version = var.postgres_major_version
  instance_class = var.instance_class

  db_name  = var.database_name
  username = "dbadmin"
  port     = var.port

  # RDS generates the password, keeps it in Secrets Manager and rotates it.
  # It never appears in this code or in Terraform state.
  manage_master_user_password = true

  storage_type          = "gp3"
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.security_group_id]
  parameter_group_name   = aws_db_parameter_group.this.name
  publicly_accessible    = false

  multi_az                = var.multi_az
  backup_retention_period = var.backup_retention_days
  copy_tags_to_snapshot   = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${local.identifier}-final"

  auto_minor_version_upgrade          = true
  iam_database_authentication_enabled = true
}
