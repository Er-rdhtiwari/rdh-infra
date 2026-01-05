provider "aws" {
  region = var.aws_region
}

locals {
  name            = "${var.name_prefix}-${var.environment}"
  tf_state_bucket = var.tf_state_bucket != "" ? var.tf_state_bucket : "${local.name}-tf-state"
  tf_lock_table   = var.tf_lock_table != "" ? var.tf_lock_table : "${local.name}-tf-lock"
}

resource "aws_s3_bucket" "tf_state" {
  bucket        = local.tf_state_bucket
  force_destroy = false

  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_dynamodb_table" "tf_lock" {
  name         = local.tf_lock_table
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

resource "aws_route53_zone" "poc" {
  count   = var.create_subdomain_zone ? 1 : 0
  name    = "poc.${var.root_domain}"
  comment = "Subdomain zone for PoCs"
}
