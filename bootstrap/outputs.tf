output "tf_state_bucket" { value = local.tf_state_bucket }
output "tf_lock_table" { value = local.tf_lock_table }
output "poc_zone_id" { value = try(aws_route53_zone.poc[0].zone_id, null) }
output "poc_zone_name_servers" { value = try(aws_route53_zone.poc[0].name_servers, []) }
