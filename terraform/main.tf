# KYEOL Main Terraform Configuration
# 모든 모듈 통합

#========================================
# VPC Module
#========================================
module "vpc" {
  source = "./modules/vpc"

  project_name               = var.project_name
  environment                = var.environment
  aws_region                 = var.aws_region
  vpc_cidr                   = var.vpc_cidr
  public_subnet_cidrs        = var.public_subnet_cidrs
  app_private_subnet_cidr    = var.app_private_subnet_cidr
  data_private_subnet_cidr   = var.data_private_subnet_cidr
  data_private_subnet_cidr_c = var.data_private_subnet_cidr_c
}

#========================================
# Security Groups Module
#========================================
module "security_groups" {
  source = "./modules/security-groups"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
}

#========================================
# RDS Module
#========================================
module "rds" {
  source = "./modules/rds"

  project_name          = var.project_name
  environment           = var.environment
  subnet_ids            = module.vpc.data_private_subnet_ids
  security_group_id     = module.security_groups.rds_sg_id
  engine_version        = var.rds_engine_version
  instance_class        = var.rds_instance_class
  db_name               = var.rds_database_name
  db_username           = var.rds_username
  allocated_storage     = var.rds_allocated_storage
  max_allocated_storage = var.rds_max_allocated_storage
}

#========================================
# ECR Module
#========================================
module "ecr" {
  source = "./modules/ecr"

  project_name = var.project_name
  environment  = var.environment
}

#========================================
# EKS Module
#========================================
module "eks" {
  source = "./modules/eks"

  project_name              = var.project_name
  environment               = var.environment
  cluster_version           = var.eks_cluster_version
  subnet_ids                = module.vpc.public_subnet_ids
  app_subnet_id             = module.vpc.app_private_subnet_id
  cluster_security_group_id = module.security_groups.app_sg_id
  node_security_group_id    = module.security_groups.app_sg_id
  node_instance_type        = var.eks_node_instance_type
  desired_capacity          = var.eks_desired_capacity
  min_capacity              = var.eks_min_capacity
  max_capacity              = var.eks_max_capacity

  depends_on = [module.vpc, module.security_groups]
}

#========================================
# ALB Module
#========================================
module "alb" {
  source = "./modules/alb"

  project_name      = var.project_name
  environment       = var.environment
  vpc_id            = module.vpc.vpc_id
  subnet_ids        = module.vpc.public_subnet_ids
  security_group_id = module.security_groups.alb_sg_id
  certificate_arn   = var.acm_certificate_arn_alb

  depends_on = [module.vpc, module.security_groups]
}

#========================================
# CloudFront Module
#========================================
module "cloudfront" {
  source = "./modules/cloudfront-s3"

  project_name = var.project_name
  environment  = var.environment
  alb_dns_name      = module.alb.alb_dns_name
  custom_domain     = var.domain_name
  certificate_arn   = var.acm_certificate_arn_cloudfront

  depends_on = [module.alb]
}

#========================================
# Backend S3 Media Upload IRSA
# Saleor Backend가 S3에 이미지 업로드할 수 있도록 설정
# 트러블슈팅 14: localhost 이미지 URL 문제 해결
#========================================

# OIDC Provider URL에서 ID 추출
locals {
  oidc_provider_id = replace(module.eks.oidc_provider_url, "https://", "")
}

# Backend S3 업로드용 IAM Policy
resource "aws_iam_policy" "backend_s3_media" {
  name        = "${var.project_name}-${var.environment}-backend-s3-media"
  description = "Allows Backend to upload media to S3"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:DeleteObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.cloudfront.s3_media_bucket_arn,
          "${module.cloudfront.s3_media_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Backend Service Account용 IAM Role (IRSA)
resource "aws_iam_role" "backend_s3_media" {
  name = "${var.project_name}-${var.environment}-role-backend-s3"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:kyeol-dev:backend-sa"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "backend_s3_media" {
  policy_arn = aws_iam_policy.backend_s3_media.arn
  role       = aws_iam_role.backend_s3_media.name
}

#========================================
# Route53 Custom Domain Record
#========================================
resource "aws_route53_record" "alias" {
  count   = var.create_custom_domain ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = module.cloudfront.cloudfront_domain_name
    zone_id                = module.cloudfront.cloudfront_hosted_zone_id
    evaluate_target_health = false
  }
}

