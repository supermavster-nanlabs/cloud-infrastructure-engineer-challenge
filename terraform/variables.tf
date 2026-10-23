variable "name" {
  description = "Name prefix for every resource."
  type        = string
  default     = "info-api"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,30}$", var.name))
    error_message = "name must be 2-31 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "IPv4 CIDR of the VPC. Subnets are /24 blocks carved from it, so use /16 or larger."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Number of availability zones to spread subnets across (2 or 3)."
  type        = number
  default     = 2
}

variable "nat_gateway_per_az" {
  description = "One NAT gateway per zone (resilient, costs more) instead of one shared gateway."
  type        = bool
  default     = false
}
