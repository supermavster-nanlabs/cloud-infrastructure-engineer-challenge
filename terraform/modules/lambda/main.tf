locals {
  handler_file = "${var.source_dir}/${split(".", var.handler)[0]}.py"
}

data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.root}/.terraform/lambda-${var.name}.zip"

  lifecycle {
    precondition {
      condition     = fileexists(local.handler_file)
      error_message = "${local.handler_file} not found. Build the package first with: make build"
    }
  }
}

# Created here so it has a retention period; Lambda would create one that never expires.
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.name}"
  retention_in_days = var.log_retention_days
}

resource "aws_iam_role" "this" {
  name = var.name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

# Logs and the network interfaces a VPC function needs (AWS offers no narrower
# scope for those actions).
resource "aws_iam_role_policy_attachment" "vpc_access" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "read_secret" {
  name = "read-database-secret"
  role = aws_iam_role.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "secretsmanager:GetSecretValue"
      Resource = var.secret_arn
    }]
  })
}

resource "aws_lambda_function" "this" {
  # checkov:skip=CKV_AWS_50: X-Ray tracing is not enabled
  # checkov:skip=CKV_AWS_115: reserved concurrency needs spare account quota that small accounts lack
  # checkov:skip=CKV_AWS_116: invoked synchronously by API Gateway, so a dead letter queue never receives anything
  # checkov:skip=CKV_AWS_173: the environment holds the secret's ARN, not a secret
  # checkov:skip=CKV_AWS_272: code signing is out of scope
  function_name = var.name
  role          = aws_iam_role.this.arn

  filename         = data.archive_file.this.output_path
  source_code_hash = data.archive_file.this.output_base64sha256
  handler          = var.handler
  runtime          = "python3.13"
  architectures    = ["arm64"]
  memory_size      = var.memory_size
  timeout          = var.timeout

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [var.security_group_id]
  }

  environment {
    variables = var.environment
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  depends_on = [aws_iam_role_policy_attachment.vpc_access, aws_iam_role_policy.read_secret]
}
