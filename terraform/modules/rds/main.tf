# RDS Module
# PostgreSQL 15.10

#========================================
# DB Subnet Group
#========================================
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-sng-rds"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-sng-rds"
  }
}

#========================================
# Parameter Group
#========================================
resource "aws_db_parameter_group" "main" {
  name   = "${var.project_name}-${var.environment}-pg-postgres15"
  family = "postgres15"

  parameter {
    name  = "log_statement"
    value = "all"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000" # 1초 이상 쿼리 로깅
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-pg-postgres15"
  }
}

#========================================
# Random Password
#========================================
resource "random_password" "db_password" {
  length  = 32
  special = false # RDS 특수문자 호환성
}

#========================================
# Secrets Manager
#========================================
resource "aws_secretsmanager_secret" "db_password" {
  name                    = "${var.project_name}-${var.environment}-rds-password"
  recovery_window_in_days = 0 # DEV 환경에서는 즉시 삭제 가능

  tags = {
    Name = "${var.project_name}-${var.environment}-rds-password"
  }
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    host     = aws_db_instance.main.address
    port     = 5432
    dbname   = var.db_name
  })
}

#========================================
# RDS Instance
#========================================
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-db-writer-01"

  # Engine
  engine         = "postgres"
  engine_version = var.engine_version
  instance_class = var.instance_class

  # Storage
  allocated_storage     = var.allocated_storage
  max_allocated_storage = var.max_allocated_storage
  storage_type          = "gp3"
  storage_encrypted     = true

  # Database - 중요: 이 설정이 없으면 503 에러 발생!
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db_password.result

  # Network
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.security_group_id]
  publicly_accessible    = false
  port                   = 5432

  # Parameter Group
  parameter_group_name = aws_db_parameter_group.main.name

  # Backup
  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Other settings
  multi_az            = false # DEV 환경에서는 단일 AZ
  skip_final_snapshot = true
  deletion_protection = false # Prod에서는 true로 설정

  tags = {
    Name = "${var.project_name}-${var.environment}-db-writer-01"
  }
}
