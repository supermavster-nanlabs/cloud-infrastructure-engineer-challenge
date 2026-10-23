variable "name" {
  description = "Function name. Also names the IAM role and the log group."
  type        = string
}

variable "source_dir" {
  description = "Directory holding the built package (code and dependencies). Created by make build."
  type        = string
}

variable "handler" {
  description = "Handler in file.function form. The file must exist in source_dir."
  type        = string
  default     = "handler.lambda_handler"
}

variable "memory_size" {
  description = "Memory in MB. CPU scales with it."
  type        = number
  default     = 256
}

variable "timeout" {
  description = "Function timeout in seconds. Keep it below the API integration timeout."
  type        = number
  default     = 15

  validation {
    condition     = var.timeout >= 1 && var.timeout <= 900
    error_message = "timeout must be between 1 and 900 seconds."
  }
}

variable "subnet_ids" {
  description = "Private subnets for the function's network interfaces."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 1
    error_message = "subnet_ids must contain at least one subnet."
  }
}

variable "security_group_id" {
  description = "Security group attached to the function's network interfaces."
  type        = string
}

variable "secret_arn" {
  description = "The one secret the function may read: the database credentials."
  type        = string
}

variable "environment" {
  description = "Environment variables. Must not hold secrets."
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "Days to keep the function's logs."
  type        = number
  default     = 14
}
