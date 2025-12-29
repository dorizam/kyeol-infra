# Security Groups Module Outputs

output "alb_sg_id" {
  description = "ALB Security Group ID"
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "App/EKS Node Security Group ID"
  value       = aws_security_group.app.id
}

output "rds_sg_id" {
  description = "RDS Security Group ID"
  value       = aws_security_group.rds.id
}
