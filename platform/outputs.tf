output "cluster_name" { value = module.eks.cluster_name }
output "cluster_endpoint" { value = module.eks.cluster_endpoint }
output "cluster_security_group_id" { value = module.eks.cluster_security_group_id }
output "oidc_provider_arn" { value = module.eks.oidc_provider_arn }
output "vpc_id" { value = module.vpc.vpc_id }

output "alb_role_arn" { value = aws_iam_role.alb.arn }
output "externaldns_role_arn" { value = aws_iam_role.externaldns.arn }
output "ebs_csi_role_arn" { value = aws_iam_role.ebs.arn }

output "acm_certificate_arn" { value = aws_acm_certificate.wildcard.arn }
output "poc_zone_id" { value = data.aws_route53_zone.poc.zone_id }
output "poc_zone_name" { value = data.aws_route53_zone.poc.name }
