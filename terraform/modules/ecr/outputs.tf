# ECR Module Outputs

output "backend_repository_url" {
  description = "Backend ECR repository URL"
  value       = aws_ecr_repository.backend.repository_url
}

output "storefront_repository_url" {
  description = "Storefront ECR repository URL"
  value       = aws_ecr_repository.storefront.repository_url
}

output "backend_repository_name" {
  description = "Backend ECR repository name"
  value       = aws_ecr_repository.backend.name
}

output "storefront_repository_name" {
  description = "Storefront ECR repository name"
  value       = aws_ecr_repository.storefront.name
}
