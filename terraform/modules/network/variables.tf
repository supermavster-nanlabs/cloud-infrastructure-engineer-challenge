variable "name" {
  description = "Name prefix for resources."
  type        = string
}

variable "cidr_block" {
  description = "IPv4 CIDR of the VPC. Each subnet is a /24 carved from it, so the prefix must be /16 or larger."
  type        = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0)) && try(tonumber(split("/", var.cidr_block)[1]) <= 16, false)
    error_message = "cidr_block must be a valid IPv4 CIDR with a prefix length of /16 or shorter."
  }
}

variable "az_count" {
  description = "Number of availability zones to use. Each gets one subnet per tier."
  type        = number

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "nat_gateway_per_az" {
  description = "Create one NAT gateway per zone instead of one shared by all zones."
  type        = bool
}

variable "db_port" {
  description = "TCP port the database listens on."
  type        = number
  default     = 5432
}
