variable "aws_region" { type = string }
variable "name_prefix" { type = string }
variable "environment" { type = string }
variable "root_domain" { type = string }
variable "create_subdomain_zone" {
  type    = bool
  default = true
}
variable "tf_state_bucket" {
  type    = string
  default = ""
}
variable "tf_lock_table" {
  type    = string
  default = ""
}
