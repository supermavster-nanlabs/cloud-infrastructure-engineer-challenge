# The whole access model in one file: who may talk to whom, and nothing else.

resource "aws_security_group" "lambda" {
  # checkov:skip=CKV2_AWS_5: attached to the function in the lambda module; checkov cannot follow module outputs
  name        = "${var.name}-lambda"
  description = "Lambda function network interfaces"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-lambda" }
}

resource "aws_security_group" "database" {
  # checkov:skip=CKV2_AWS_5: attached to the database in the database module; checkov cannot follow module outputs
  name        = "${var.name}-database"
  description = "PostgreSQL database"
  vpc_id      = aws_vpc.this.id

  tags = { Name = "${var.name}-database" }
}

resource "aws_vpc_security_group_egress_rule" "lambda_to_database" {
  security_group_id            = aws_security_group.lambda.id
  description                  = "Query the database"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.database.id
}

# Secrets Manager is a public endpoint reached through the NAT gateway. AWS
# publishes no prefix list for it, hence the open destination.
resource "aws_vpc_security_group_egress_rule" "lambda_to_aws_apis" {
  security_group_id = aws_security_group.lambda.id
  description       = "HTTPS to AWS APIs through the NAT gateway"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# The database has no egress rule: replies to allowed connections need none.
resource "aws_vpc_security_group_ingress_rule" "database_from_lambda" {
  security_group_id            = aws_security_group.database.id
  description                  = "Queries from the Lambda function"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = aws_security_group.lambda.id
}
