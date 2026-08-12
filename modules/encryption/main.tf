data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "kms_key_policy" {
  statement {
    sid       = "EnableIAMRootPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_admin_arns) > 0 ? [1] : []
    content {
      sid    = "AllowKeyAdministration"
      effect = "Allow"
      actions = [
        "kms:Create*",
        "kms:Describe*",
        "kms:Enable*",
        "kms:List*",
        "kms:Put*",
        "kms:Update*",
        "kms:Revoke*",
        "kms:Disable*",
        "kms:Get*",
        "kms:Delete*",
        "kms:TagResource",
        "kms:UntagResource",
        "kms:ScheduleKeyDeletion",
        "kms:CancelKeyDeletion",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.kms_admin_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.kms_user_arns) > 0 ? [1] : []
    content {
      sid    = "AllowKeyUse"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
        "kms:CreateGrant",
        "kms:ListGrants",
        "kms:RetireGrant",
      ]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.kms_user_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = var.enabled ? 1 : 0

  description             = "${var.name_prefix} customer master key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_key_policy.json

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  count = var.enabled ? 1 : 0

  name          = "alias/${var.name_prefix}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_ebs_encryption_by_default" "this" {
  count = var.enabled && var.ebs_encryption_enabled ? 1 : 0

  enabled = true
}

resource "aws_s3_account_public_access_block" "this" {
  count = var.s3_account_public_access_block.enabled ? 1 : 0

  block_public_acls       = var.s3_account_public_access_block.block_public_acls
  block_public_policy     = var.s3_account_public_access_block.block_public_policy
  ignore_public_acls      = var.s3_account_public_access_block.ignore_public_acls
  restrict_public_buckets = var.s3_account_public_access_block.restrict_public_buckets
}
