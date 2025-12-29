# EKS Module Variables

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "cluster_version" {
  type    = string
  default = "1.33"
}

variable "subnet_ids" {
  description = "Subnets for EKS cluster (control plane)"
  type        = list(string)
}

variable "app_subnet_id" {
  description = "Subnet for EKS worker nodes"
  type        = string
}

variable "cluster_security_group_id" {
  description = "Security group for EKS cluster"
  type        = string
}

variable "node_security_group_id" {
  description = "Security group for EKS worker nodes"
  type        = string
}

variable "node_instance_type" {
  type    = string
  default = "t3.large"
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "min_capacity" {
  type    = number
  default = 1
}

variable "max_capacity" {
  type    = number
  default = 4
}
