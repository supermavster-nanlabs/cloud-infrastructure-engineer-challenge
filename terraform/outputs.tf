output "vpc_id" {
  description = "ID of the VPC."
  value       = module.network.vpc_id
}

output "nat_public_ips" {
  description = "Public IPs the private subnets' outbound traffic comes from."
  value       = module.network.nat_public_ips
}
