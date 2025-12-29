# KYEOL Terraform Outputs

#========================================
# VPC Outputs
#========================================
output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "app_private_subnet_id" {
  description = "App private subnet ID"
  value       = module.vpc.app_private_subnet_id
}

#========================================
# EKS Outputs
#========================================
output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "EKS OIDC provider ARN for IRSA"
  value       = module.eks.oidc_provider_arn
}

output "kubeconfig_command" {
  description = "Command to configure kubectl"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

#========================================
# RDS Outputs
#========================================
output "rds_endpoint" {
  description = "RDS endpoint"
  value       = module.rds.db_endpoint
}

output "rds_database_name" {
  description = "RDS database name"
  value       = module.rds.db_name
}

output "rds_secret_arn" {
  description = "Secrets Manager ARN for RDS password"
  value       = module.rds.db_password_secret_arn
}

#========================================
# ECR Outputs
#========================================
output "ecr_backend_url" {
  description = "Backend ECR repository URL"
  value       = module.ecr.backend_repository_url
}

output "ecr_storefront_url" {
  description = "Storefront ECR repository URL"
  value       = module.ecr.storefront_repository_url
}

#========================================
# ALB Outputs
#========================================
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = module.alb.alb_dns_name
}

output "backend_target_group_arn" {
  description = "Backend target group ARN"
  value       = module.alb.backend_target_group_arn
}

output "storefront_target_group_arn" {
  description = "Storefront target group ARN"
  value       = module.alb.storefront_target_group_arn
}

#========================================
# CloudFront Outputs
#========================================
output "cloudfront_domain_name" {
  description = "CloudFront domain name"
  value       = module.cloudfront.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = module.cloudfront.cloudfront_distribution_id
}

output "s3_static_bucket_name" {
  description = "S3 bucket name for static assets"
  value       = module.cloudfront.s3_bucket_name
}

output "custom_domain_name" {
  description = "Custom domain name"
  value       = var.domain_name
}

#========================================
# Convenience Outputs
#========================================
output "storefront_url" {
  description = "Storefront URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}" : "https://${module.cloudfront.cloudfront_domain_name}"
}

output "dashboard_url" {
  description = "Dashboard URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}/dashboard/" : "https://${module.cloudfront.cloudfront_domain_name}/dashboard/"
}

output "graphql_url" {
  description = "GraphQL API URL"
  value       = var.domain_name != "" ? "https://${var.domain_name}/graphql/" : "https://${module.cloudfront.cloudfront_domain_name}/graphql/"
}

#========================================
# S3 Media Outputs
#========================================
output "s3_media_bucket_name" {
  description = "S3 bucket name for media assets"
  value       = module.cloudfront.s3_media_bucket_name
}

output "backend_s3_role_arn" {
  description = "IAM Role ARN for Backend S3 access (IRSA)"
  value       = aws_iam_role.backend_s3_media.arn
}
