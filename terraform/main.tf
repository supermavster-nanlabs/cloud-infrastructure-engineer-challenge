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
