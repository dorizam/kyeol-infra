# VPC Module
# DEV VPC: 10.10.0.0/16

#========================================
# VPC
#========================================
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc"
  }
}

#========================================
# Internet Gateway
#========================================
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-${var.environment}-igw"
  }
}

#========================================
# Public Subnets (Multi-AZ for ALB)
#========================================
resource "aws_subnet" "public" {
  for_each = var.public_subnet_cidrs

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = "${var.aws_region}${each.key}"
  map_public_ip_on_launch = true

  tags = {
    Name                                                               = "${var.project_name}-${var.environment}-sub-pub-${each.key}"
    "kubernetes.io/role/elb"                                           = "1"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}-eks" = "shared"
  }
}

#========================================
# App Private Subnet (EKS Worker Nodes - AZ-A)
#========================================
resource "aws_subnet" "app_private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.app_private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name                                                               = "${var.project_name}-${var.environment}-sub-app-pri-a"
    "kubernetes.io/role/internal-elb"                                  = "1"
    "kubernetes.io/cluster/${var.project_name}-${var.environment}-eks" = "shared"
  }
}

#========================================
# Data Private Subnets (RDS - Multi-AZ Subnet Group용)
#========================================
resource "aws_subnet" "data_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_private_subnet_cidr
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "${var.project_name}-${var.environment}-sub-data-pri-a"
  }
}

resource "aws_subnet" "data_private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.data_private_subnet_cidr_c
  availability_zone = "${var.aws_region}c"

  tags = {
    Name = "${var.project_name}-${var.environment}-sub-data-pri-c"
  }
}

#========================================
# Elastic IP for NAT Gateway
#========================================
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.project_name}-${var.environment}-eip-nat-a"
  }

  depends_on = [aws_internet_gateway.main]
}

#========================================
# NAT Gateway (Single AZ for DEV - 비용 절감)
#========================================
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public["a"].id

  tags = {
    Name = "${var.project_name}-${var.environment}-nat-a"
  }

  depends_on = [aws_internet_gateway.main]
}

#========================================
# Route Tables
#========================================
# Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-pub"
  }
}

# Private Route Table (NAT Gateway 경유)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-rt-pri-a"
  }
}

#========================================
# Route Table Associations
#========================================
resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "app_private" {
  subnet_id      = aws_subnet.app_private.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data_private_a" {
  subnet_id      = aws_subnet.data_private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "data_private_c" {
  subnet_id      = aws_subnet.data_private_c.id
  route_table_id = aws_route_table.private.id
}

#========================================
# VPC Flow Logs
#========================================
resource "aws_flow_log" "main" {
  vpc_id               = aws_vpc.main.id
  traffic_type         = "ALL"
  log_destination_type = "cloud-watch-logs"
  log_destination      = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn         = aws_iam_role.flow_logs.arn

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-flowlog"
  }
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  name              = "/aws/vpc/${var.project_name}-${var.environment}-flowlogs"
  retention_in_days = 30
}

resource "aws_iam_role" "flow_logs" {
  name = "${var.project_name}-${var.environment}-role-flowlogs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "vpc-flow-logs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${var.project_name}-${var.environment}-policy-flowlogs"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Effect   = "Allow"
      Resource = "*"
    }]
  })
}
