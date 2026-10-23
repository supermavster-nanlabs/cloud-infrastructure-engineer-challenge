variable "name" {
  description = "Name prefix for the topic and the alarms."
  type        = string
}

variable "alert_email" {
  description = "Address that receives alerts. AWS emails a link that must be clicked to confirm. Null creates the topic with no subscriber."
  type        = string
  default     = null
}

variable "db_instance_identifier" {
  description = "RDS instance to watch."
  type        = string
}

variable "lambda_function_name" {
  description = "Lambda function to watch."
  type        = string
}

variable "api_id" {
  description = "HTTP API to watch."
  type        = string
}
