data "aws_iam_policy_document" "alb_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "alb" {
  name               = "${local.name}-alb-iam"
  assume_role_policy = data.aws_iam_policy_document.alb_assume.json
}
resource "aws_iam_policy" "alb" {
  name   = "${local.name}-alb-policy"
  policy = file("${path.module}/policies/aws-load-balancer-controller.json")
}
resource "aws_iam_role_policy_attachment" "alb_attach" {
  role       = aws_iam_role.alb.name
  policy_arn = aws_iam_policy.alb.arn
}

data "aws_iam_policy_document" "externaldns_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:external-dns"]
    }
  }
}

resource "aws_iam_role" "externaldns" {
  name               = "${local.name}-externaldns-iam"
  assume_role_policy = data.aws_iam_policy_document.externaldns_assume.json
}
resource "aws_iam_policy" "externaldns" {
  name   = "${local.name}-externaldns-policy"
  policy = file("${path.module}/policies/external-dns.json")
}
resource "aws_iam_role_policy_attachment" "externaldns_attach" {
  role       = aws_iam_role.externaldns.name
  policy_arn = aws_iam_policy.externaldns.arn
}

data "aws_iam_policy_document" "ebs_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"
    principals {
      type        = "Federated"
      identifiers = [module.eks.oidc_provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }
  }
}

resource "aws_iam_role" "ebs" {
  name               = "${local.name}-ebs-csi-iam"
  assume_role_policy = data.aws_iam_policy_document.ebs_assume.json
}
resource "aws_iam_policy" "ebs" {
  name   = "${local.name}-ebs-csi-policy"
  policy = file("${path.module}/policies/ebs-csi-driver.json")
}
resource "aws_iam_role_policy_attachment" "ebs_attach" {
  role       = aws_iam_role.ebs.name
  policy_arn = aws_iam_policy.ebs.arn
}
