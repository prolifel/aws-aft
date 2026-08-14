locals {
  ci_enabled = var.enabled && var.management_account
  oidc_host  = replace(var.gitlab_url, "https://", "")
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  count = local.ci_enabled ? 1 : 0

  url             = var.gitlab_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.oidc_thumbprint != null ? [var.oidc_thumbprint] : []
}

data "aws_iam_policy_document" "gitlab_ci_trust" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gitlab[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = ["project_path:${var.gitlab_project_path}:ref_type:branch:ref:${var.gitlab_branch}"]
    }
  }
}

resource "aws_iam_role" "gitlab_ci" {
  count = local.ci_enabled ? 1 : 0

  name               = "${var.name_prefix}-gitlab-ci"
  assume_role_policy = data.aws_iam_policy_document.gitlab_ci_trust[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "servicecatalog" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "servicecatalog:DescribeProduct",
      "servicecatalog:DescribeProductAsAdmin",
      "servicecatalog:DescribeProvisionedProduct",
      "servicecatalog:ListProvisioningArtifacts",
      "servicecatalog:ProvisionProduct",
      "servicecatalog:SearchProductsAsAdmin",
      "servicecatalog:TerminateProvisionedProduct",
      "servicecatalog:UpdateProvisionedProduct",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "management_plane" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "cloudtrail:*",
      "config:*",
      "ec2:*",
      "guardduty:*",
      "iam:*",
      "identitystore:*",
      "inspector2:*",
      "kms:*",
      "logs:*",
      "macie2:*",
      "organizations:*",
      "s3:*",
      "securityhub:*",
      "sns:*",
      "sso-admin:*",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "config_bucket" {
  count = local.ci_enabled && var.config_bucket_arn != "" ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.config_bucket_arn}/*"]
  }
}

data "aws_iam_policy_document" "cross_account" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [
      "arn:aws:iam::*:role/AWSControlTowerExecution",
      "arn:aws:iam::*:role/${var.deploy_role_name}",
    ]
  }
}

resource "aws_iam_role_policy" "servicecatalog" {
  count = local.ci_enabled ? 1 : 0

  name   = "servicecatalog"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.servicecatalog[0].json
}

resource "aws_iam_role_policy" "management_plane" {
  count = local.ci_enabled ? 1 : 0

  name   = "management-plane"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.management_plane[0].json
}

resource "aws_iam_role_policy" "config_bucket" {
  count = local.ci_enabled && var.config_bucket_arn != "" ? 1 : 0

  name   = "config-bucket"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.config_bucket[0].json
}

resource "aws_iam_role_policy" "cross_account" {
  count = local.ci_enabled ? 1 : 0

  name   = "cross-account"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.cross_account[0].json
}
