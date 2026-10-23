variable "name" {
  description = "Name prefix. The instance identifier is <name>-db."
  type        = string
}

variable "subnet_ids" {
  description = "Isolated subnets for the database, in at least two availability zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "subnet_ids must contain at least two subnets in different availability zones."
  }
}

variable "security_group_id" {
  description = "Security group attached to the database."
  type        = string
}

variable "postgres_major_version" {
  description = "PostgreSQL major version. RDS picks the minor version and upgrades it automatically."
  type        = string
  default     = "17"
}

variable "instance_class" {
  description = "RDS instance class."
  type        = string
}

variable "allocated_storage" {
  description = "Initial storage in GiB."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling ceiling in GiB. Must be larger than allocated_storage."
  type        = number
  default     = 50

  validation {
    condition     = var.max_allocated_storage > var.allocated_storage
    error_message = "max_allocated_storage must be larger than allocated_storage."
  }
}

variable "multi_az" {
  description = "Keep a synchronous standby in a second zone and fail over automatically."
  type        = bool
}

variable "backup_retention_days" {
  description = "Days to keep automated backups, which also sets the point-in-time restore window."
  type        = number

  validation {
    condition     = var.backup_retention_days >= 1 && var.backup_retention_days <= 35
    error_message = "backup_retention_days must be between 1 and 35."
  }
}

variable "deletion_protection" {
  description = "Refuse to delete the instance while true."
  type        = bool
}

variable "skip_final_snapshot" {
  description = "Skip the snapshot taken when the instance is deleted."
  type        = bool
}

variable "port" {
  description = "TCP port the database listens on."
  type        = number
  default     = 5432
}

variable "database_name" {
  description = "Name of the initial database."
  type        = string
  default     = "appdb"
}
