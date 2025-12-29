# RDS Module Variables

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "subnet_ids" {
  description = "Subnet IDs for RDS subnet group"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for RDS"
  type        = string
}

variable "engine_version" {
  type    = string
  default = "15.10"
}

variable "instance_class" {
  type    = string
  default = "db.t3.medium"
}

variable "db_name" {
  type    = string
  default = "saleor"
}

variable "db_username" {
  type    = string
  default = "saleor_admin"
}

variable "allocated_storage" {
  type    = number
  default = 20
}

variable "max_allocated_storage" {
  type    = number
  default = 100
}
