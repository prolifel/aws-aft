locals {
  ci_enabled       = var.enabled && var.management_account
  oidc_host        = replace(var.gitlab_url, "https://", "")
  state_bucket_arn = "arn:aws:s3:::${var.state_bucket_name}"
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  count = local.ci_enabled ? 1 : 0

  url             = var.gitlab_url
  client_id_list  = [var.gitlab_url]
  thumbprint_list = var.oidc_thumbprint == null ? [] : [var.oidc_thumbprint]
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
      values   = [var.gitlab_url]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values = [
        "project_path:${var.gitlab_project_path}:ref_type:branch:ref:${var.gitlab_branch}",
        "project_path:${var.gitlab_project_path}:ref_type:merge_request_event:ref:*",
      ]
    }
  }
}

resource "aws_iam_role" "gitlab_ci" {
  count = local.ci_enabled ? 1 : 0

  name               = "${var.name_prefix}-gitlab-ci"
  assume_role_policy = data.aws_iam_policy_document.gitlab_ci_trust[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "vending" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "servicecatalog:DescribeProduct",
      "servicecatalog:DescribeProvisionedProduct",
      "servicecatalog:ListProvisioningArtifacts",
      "servicecatalog:ProvisionProduct",
      "servicecatalog:UpdateProvisionedProduct",
      "organizations:DescribeOrganization",
      "organizations:ListAccounts",
      "organizations:ListChildren",
      "organizations:ListOrganizationalUnitsForParent",
      "organizations:ListRoots",
      "sts:AssumeRole",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [local.state_bucket_arn, "${local.state_bucket_arn}/*"]
  }

  dynamic "statement" {
    for_each = var.state_kms_key_arn == "" ? [] : [var.state_kms_key_arn]
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_role_policy" "vending" {
  count = local.ci_enabled ? 1 : 0

  name   = "account-vending"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.vending[0].json
}
