output "api_id" {
  description = "ID of the API. It is the ApiId dimension of the API Gateway metrics."
  value       = aws_apigatewayv2_api.this.id
}

output "route_url" {
  description = "Full URL of the route."
  value       = "${aws_apigatewayv2_api.this.api_endpoint}${local.route_path}"
}
