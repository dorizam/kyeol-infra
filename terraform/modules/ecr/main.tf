# ECR Module

#========================================
# Backend ECR Repository
#========================================
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-${var.environment}-backend"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # terraform destroy 시 이미지가 있어도 강제 삭제

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-backend"
  }
}

#========================================
# Storefront ECR Repository
#========================================
resource "aws_ecr_repository" "storefront" {
  name                 = "${var.project_name}-${var.environment}-storefront"
  image_tag_mutability = "MUTABLE"
  force_delete         = true  # terraform destroy 시 이미지가 있어도 강제 삭제

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-storefront"
  }
}

#========================================
# ECR Lifecycle Policy (이미지 정리)
#========================================
resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "storefront" {
  repository = aws_ecr_repository.storefront.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
