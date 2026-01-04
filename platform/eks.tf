resource "aws_security_group" "alb" {
  name        = "${local.name}-alb-sg"
  description = "ALB SG"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name}-alb-sg" }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.4"

  cluster_name    = "${var.name_prefix}-${var.environment}-eks"
  cluster_version = var.kubernetes_version

  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true
  vpc_id                         = module.vpc.vpc_id
  enable_irsa                    = true

  eks_managed_node_groups = {
    default = {
      instance_types = split(",", var.node_instance_types)
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      desired_size   = var.node_desired_size
      subnet_ids     = module.vpc.private_subnets
    }
  }

  node_security_group_additional_rules = {
    ingress_allow_alb = {
      description              = "Allow ALB to reach nodes/pods"
      protocol                 = "-1"
      from_port                = 0
      to_port                  = 0
      type                     = "ingress"
      source_security_group_id = aws_security_group.alb.id
    }
  }
}
