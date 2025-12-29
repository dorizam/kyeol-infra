# VPC Module Variables

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "public_subnet_cidrs" {
  type = map(string)
}

variable "app_private_subnet_cidr" {
  type = string
}

variable "data_private_subnet_cidr" {
  type = string
}

variable "data_private_subnet_cidr_c" {
  type = string
}
