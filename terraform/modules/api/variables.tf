variable "name" {
  description = "Name of the API. Also names the access log group."
  type        = string
}

variable "lambda_function_name" {
  description = "Function API Gateway is allowed to invoke."
  type        = string
}

variable "lambda_invoke_arn" {
  description = "Invoke ARN of the function."
  type        = string
}

variable "route_key" {
  description = "HTTP method and path served by the function."
  type        = string
  default     = "GET /info"

  validation {
    condition     = can(regex("^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) /[A-Za-z0-9/_-]*$", var.route_key))
    error_message = "route_key must be an HTTP method and an absolute path without variables, for example GET /info."
  }
}

variable "integration_timeout_ms" {
  description = "How long API Gateway waits for the function. Keep it above the function timeout. HTTP APIs allow at most 30000."
  type        = number

  validation {
    condition     = var.integration_timeout_ms >= 50 && var.integration_timeout_ms <= 30000
    error_message = "integration_timeout_ms must be between 50 and 30000."
  }
}

variable "throttling_rate_limit" {
  description = "Steady-state requests per second. Excess requests get HTTP 429."
  type        = number
  default     = 5
}

variable "throttling_burst_limit" {
  description = "Short burst of requests accepted above the steady rate."
  type        = number
  default     = 10
}

variable "log_retention_days" {
  description = "Days to keep access logs."
  type        = number
  default     = 14
}
