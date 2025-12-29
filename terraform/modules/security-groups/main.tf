# Security Groups Module
# Chained Security Group 방식 (IP가 아닌 SG ID 참조)

#========================================
# ALB Security Group
#========================================
resource "aws_security_group" "alb" {
  name        = "${var.project_name}-${var.environment}-sg-alb"
  description = "Security group for Application Load Balancer"
  vpc_id      = var.vpc_id

  # HTTP 인바운드
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from anywhere"
  }

  # HTTPS 인바운드
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from anywhere"
  }

  # Backend API 아웃바운드
  egress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "Backend API to App nodes"
  }

  # Storefront 아웃바운드
  egress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "Storefront to App nodes"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-alb"
  }
}

#========================================
# App/EKS Node Security Group
#========================================
resource "aws_security_group" "app" {
  name        = "${var.project_name}-${var.environment}-sg-app"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-app"
  }
}

# App SG Ingress Rules (순환참조 방지를 위해 별도 리소스)
resource "aws_security_group_rule" "app_backend_from_alb" {
  type                     = "ingress"
  from_port                = 8000
  to_port                  = 8000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.app.id
  description              = "Backend API from ALB"
}

resource "aws_security_group_rule" "app_storefront_from_alb" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.app.id
  description              = "Storefront from ALB"
}

resource "aws_security_group_rule" "app_https_from_alb" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.app.id
  description              = "HTTPS from ALB (health checks)"
}

# Node to Node 통신
resource "aws_security_group_rule" "app_self" {
  type              = "ingress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.app.id
  description       = "Node to node communication"
}

# 전체 아웃바운드 (SSM, NAT Gateway, 외부 API)
resource "aws_security_group_rule" "app_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.app.id
  description       = "All outbound traffic (SSM, NAT, APIs)"
}

#========================================
# RDS Security Group
#========================================
resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-sg-rds"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id

  # PostgreSQL from App nodes only (Chained)
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
    description     = "PostgreSQL from App nodes"
  }

  # 아웃바운드 없음 (RDS는 수동 연결만)

  tags = {
    Name = "${var.project_name}-${var.environment}-sg-rds"
  }
}
