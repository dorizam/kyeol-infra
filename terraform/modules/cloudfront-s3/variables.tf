# CloudFront Module Variables

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "alb_dns_name" {
  description = "ALB DNS name for dynamic origin"
  type        = string
}

variable "custom_domain" {
  description = "Custom domain name (optional)"
  type        = string
  default     = ""
}

variable "certificate_arn" {
  description = "ACM Certificate ARN for CloudFront (optional)"
  type        = string
  default     = ""
}
