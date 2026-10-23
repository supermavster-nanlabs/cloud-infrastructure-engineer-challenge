data "aws_availability_zones" "available" {
  # checkov:skip=CKV_AWS_394: only the first az_count zones by name are used, and new zones sort last
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs      = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  az_index = { for index, az in local.azs : az => index }

  # Every subnet is a /24. The offsets keep the tiers apart and leave room for a third zone.
  subnet_newbits = 24 - tonumber(split("/", var.cidr_block)[1])
  tier_offsets   = { public = 0, app = 10, data = 20 }

  nat_azs        = var.nat_gateway_per_az ? local.az_index : { (local.azs[0]) = 0 }
  nat_az_for_app = { for az in local.azs : az => var.nat_gateway_per_az ? az : local.azs[0] }
}

resource "aws_vpc" "this" {
  # checkov:skip=CKV2_AWS_11: flow logs are left out to keep the stack small; see docs/decisions.md
  cidr_block           = var.cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

resource "aws_subnet" "public" {
  for_each = local.az_index

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = cidrsubnet(var.cidr_block, local.subnet_newbits, local.tier_offsets.public + each.value)
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "app" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr_block, local.subnet_newbits, local.tier_offsets.app + each.value)

  tags = { Name = "${var.name}-app-${each.key}", Tier = "app" }
}

resource "aws_subnet" "data" {
  for_each = local.az_index

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = cidrsubnet(var.cidr_block, local.subnet_newbits, local.tier_offsets.data + each.value)

  tags = { Name = "${var.name}-data-${each.key}", Tier = "data" }
}

resource "aws_eip" "nat" {
  for_each = local.nat_azs

  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]

  tags = { Name = "${var.name}-nat-${each.key}" }
}

resource "aws_nat_gateway" "this" {
  for_each = local.nat_azs

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  depends_on    = [aws_internet_gateway.this]

  tags = { Name = "${var.name}-nat-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-public" }
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "app" {
  for_each = local.az_index

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-app-${each.key}" }
}

resource "aws_route" "app_nat" {
  for_each = local.az_index

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[local.nat_az_for_app[each.key]].id
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# The data tier has no route beyond the VPC: the database cannot reach or be
# reached from the internet.
resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-data" }
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data.id
}

# Declared without rules so the VPC's default group allows nothing.
resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-unused" }
}
