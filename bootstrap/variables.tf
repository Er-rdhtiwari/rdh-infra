variable "aws_region" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "root_domain" { type = string }
variable "create_subdomain_zone" {
  type    = bool
  default = true
}
