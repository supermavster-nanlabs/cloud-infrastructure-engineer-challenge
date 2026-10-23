module "network" {
  source = "./modules/network"

  name               = var.name
  cidr_block         = var.vpc_cidr_block
  az_count           = var.az_count
  nat_gateway_per_az = var.nat_gateway_per_az
}
