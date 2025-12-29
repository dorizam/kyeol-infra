# KYEOL 프로젝트 변수 정의

#========================================
# 공통 설정
#========================================
variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name (dev, stage, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name prefix for naming convention"
  type        = string
  default     = "kyeol"
}

#========================================
# VPC & 네트워크 설정
#========================================
variable "vpc_cidr" {
  description = "VPC CIDR block (DEV: 10.10.0.0/16)"
  type        = string
  default     = "10.10.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs by AZ"
  type        = map(string)
  default = {
    "a" = "10.10.0.0/24" # 외부 통신용
    "c" = "10.10.1.0/24" # 고가용성 보조
  }
}

variable "app_private_subnet_cidr" {
  description = "App Private subnet CIDR (EKS Worker Nodes)"
  type        = string
  default     = "10.10.4.0/22"
}

variable "data_private_subnet_cidr" {
  description = "Data Private subnet CIDR (RDS)"
  type        = string
  default     = "10.10.9.0/24"
}

# RDS Multi-AZ를 위한 추가 서브넷
variable "data_private_subnet_cidr_c" {
  description = "Data Private subnet CIDR AZ-C (RDS Subnet Group용)"
  type        = string
  default     = "10.10.10.0/24"
}

#========================================
# EKS 설정
#========================================
variable "eks_cluster_version" {
  description = "EKS Kubernetes version"
  type        = string
  default     = "1.33" # AWS EKS 표준 지원 버전
}

variable "eks_node_instance_type" {
  description = "EKS worker node instance type"
  type        = string
  default     = "t3.large"
}

variable "eks_desired_capacity" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

variable "eks_min_capacity" {
  description = "Minimum number of EKS worker nodes"
  type        = number
  default     = 1
}

variable "eks_max_capacity" {
  description = "Maximum number of EKS worker nodes"
  type        = number
  default     = 4
}

#========================================
# RDS 설정
#========================================
variable "rds_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.m5.large"
}

variable "rds_engine_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "15.10"
}

variable "rds_database_name" {
  description = "Database name (중요: 없으면 503 에러)"
  type        = string
  default     = "saleor"
}

variable "rds_username" {
  description = "Database master username"
  type        = string
  default     = "saleor_admin"
}

variable "rds_allocated_storage" {
  description = "Initial allocated storage (GB)"
  type        = number
  default     = 20
}

variable "rds_max_allocated_storage" {
  description = "Maximum allocated storage for autoscaling (GB)"
  type        = number
  default     = 100
}

#========================================
# 도메인 설정 (추후 커스텀 도메인용)
#========================================
variable "domain_name" {
  description = "Custom domain name (optional)"
  type        = string
  default     = "" # 비워두면 CloudFront 기본 도메인 사용
}

variable "create_custom_domain" {
  description = "Whether to create custom domain resources"
  type        = bool
  default     = false
}

variable "acm_certificate_arn_cloudfront" {
  description = "ACM Certificate ARN for CloudFront (us-east-1)"
  type        = string
  default     = ""
}

variable "acm_certificate_arn_alb" {
  description = "ACM Certificate ARN for ALB (ap-northeast-2)"
  type        = string
  default     = ""
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID for DNS records"
  type        = string
  default     = ""
}
