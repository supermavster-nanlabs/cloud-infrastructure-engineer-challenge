module "network" {
  source = "./modules/network"

  name               = var.name
  cidr_block         = var.vpc_cidr_block
  az_count           = var.az_count
  nat_gateway_per_az = var.nat_gateway_per_az
}

module "database" {
  source = "./modules/database"

  name                  = var.name
  subnet_ids            = module.network.data_subnet_ids
  security_group_id     = module.network.database_security_group_id
  instance_class        = var.db_instance_class
  multi_az              = var.db_multi_az
  backup_retention_days = var.db_backup_retention_days
  deletion_protection   = var.db_deletion_protection
  skip_final_snapshot   = var.db_skip_final_snapshot
}

module "lambda" {
  source = "./modules/lambda"

  name              = "${var.name}-info"
  source_dir        = var.lambda_package_dir
  timeout           = var.lambda_timeout_seconds
  subnet_ids        = module.network.app_subnet_ids
  security_group_id = module.network.lambda_security_group_id
  secret_arn        = module.database.master_secret_arn

  environment = {
    DB_HOST           = module.database.address
    DB_PORT           = tostring(module.database.port)
    DB_NAME           = module.database.database_name
    DB_SECRET_ARN     = module.database.master_secret_arn
    DB_INSTANCE_CLASS = module.database.details.class
    DB_MULTI_AZ       = tostring(module.database.details.multi_az)
    DB_AZ             = module.database.details.availability_zone
    DB_BACKUP_DAYS    = tostring(module.database.details.backup_retention_days)
  }
}

module "api" {
  source = "./modules/api"

  name                   = "${var.name}-info"
  lambda_function_name   = module.lambda.function_name
  lambda_invoke_arn      = module.lambda.invoke_arn
  integration_timeout_ms = (var.lambda_timeout_seconds + 1) * 1000
  throttling_rate_limit  = var.api_throttling_rate_limit
  throttling_burst_limit = var.api_throttling_burst_limit
}
