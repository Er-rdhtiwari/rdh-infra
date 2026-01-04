output "tf_state_bucket" { value = aws_s3_bucket.tf_state.bucket }
output "tf_lock_table" { value = aws_dynamodb_table.tf_lock.name }
output "poc_zone_id" { value = try(aws_route53_zone.poc[0].zone_id, null) }
output "poc_zone_name_servers" { value = try(aws_route53_zone.poc[0].name_servers, []) }
