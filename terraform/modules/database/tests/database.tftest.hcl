mock_provider "aws" {}

variables {
  name                  = "info-api"
  subnet_ids            = ["subnet-0aaaaaaaaaaaaaaaa", "subnet-0bbbbbbbbbbbbbbbb"]
  security_group_id     = "sg-0123456789abcdef0"
  instance_class        = "db.t4g.micro"
  multi_az              = false
  backup_retention_days = 7
  deletion_protection   = false
  skip_final_snapshot   = true
}

run "database_is_private_encrypted_and_has_no_password_in_code" {
  command = plan

  assert {
    condition = (
      aws_db_instance.this.publicly_accessible == false &&
      aws_db_instance.this.storage_encrypted &&
      aws_db_instance.this.manage_master_user_password &&
      aws_db_instance.this.password == null
    )
    error_message = "The database must be private and encrypted, with a password managed by RDS and none set here."
  }
}

run "tls_is_required" {
  command = plan

  assert {
    condition = (
      aws_db_parameter_group.this.family == "postgres17" &&
      { for p in aws_db_parameter_group.this.parameter : p.name => p.value }["rds.force_ssl"] == "1"
    )
    error_message = "Connections without TLS must be rejected."
  }
}

run "tls_setting_matches_what_rds_reports" {
  command = plan

  assert {
    condition     = { for p in aws_db_parameter_group.this.parameter : p.name => p.apply_method }["rds.force_ssl"] == "pending-reboot"
    error_message = "RDS reports rds.force_ssl as pending-reboot; any other method makes every plan show a change."
  }
}

run "multi_az_and_backups_follow_the_inputs" {
  command = plan

  variables {
    multi_az              = true
    backup_retention_days = 14
  }

  assert {
    condition     = aws_db_instance.this.multi_az && aws_db_instance.this.backup_retention_period == 14
    error_message = "multi_az and backup_retention_days must reach the instance."
  }
}

run "rejects_a_single_subnet" {
  command = plan

  variables {
    subnet_ids = ["subnet-0aaaaaaaaaaaaaaaa"]
  }

  expect_failures = [var.subnet_ids]
}
