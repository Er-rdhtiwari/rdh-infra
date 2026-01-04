variable "aws_region" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "root_domain" { type = string }

variable "vpc_cidr" { type = string }
variable "public_subnet_cidrs" { type = string }
variable "private_subnet_cidrs" { type = string }

variable "kubernetes_version" { type = string }
variable "node_instance_types" { type = string }
variable "node_min_size" { type = number }
variable "node_max_size" { type = number }
variable "node_desired_size" { type = number }

variable "externaldns_txt_owner_id" { type = string }
