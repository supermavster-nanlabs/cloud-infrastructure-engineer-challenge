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

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t4g.micro"
}

variable "db_multi_az" {
  description = "Run a synchronous standby in a second zone with automatic failover. Off by default to keep a test deployment cheap."
  type        = bool
  default     = false
}

variable "db_backup_retention_days" {
  description = "Days to keep automated database backups (1-35). Sets the point-in-time restore window."
  type        = number
  default     = 7
}

variable "db_deletion_protection" {
  description = "Refuse to delete the database while true. Off by default so a test deployment can be destroyed; turn it on in production."
  type        = bool
  default     = false
}

variable "db_skip_final_snapshot" {
  description = "Skip the snapshot taken when the database is deleted. Set to false in production."
  type        = bool
  default     = true
}
