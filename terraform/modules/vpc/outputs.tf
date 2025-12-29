# VPC Module Outputs

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = [for s in aws_subnet.public : s.id]
}

output "app_private_subnet_id" {
  description = "App private subnet ID"
  value       = aws_subnet.app_private.id
}

output "data_private_subnet_ids" {
  description = "Data private subnet IDs (RDS Subnet Group용)"
  value       = [aws_subnet.data_private_a.id, aws_subnet.data_private_c.id]
}

output "nat_gateway_id" {
  description = "NAT Gateway ID"
  value       = aws_nat_gateway.main.id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID"
  value       = aws_internet_gateway.main.id
}
