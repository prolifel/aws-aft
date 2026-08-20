locals {
  scp_enabled = var.enabled && var.management_account
}

data "aws_iam_policy_document" "deny_iam_user_creations" {
  statement {
    sid       = "DenyIAMUserCreations"
    effect    = "Deny"
    actions   = ["iam:CreateUser", "iam:CreateAccessKey"]
    resources = ["*"]
    dynamic "condition" {
      for_each = length(var.break_glass_exempt_arns) > 0 ? [1] : []
      content {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = var.break_glass_exempt_arns
      }
    }
  }
}

data "aws_iam_policy_document" "require_mfa" {
  statement {
    sid       = "DenyWithoutMFA"
    effect    = "Deny"
    actions   = ["*"]
    resources = ["*"]
    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
    dynamic "condition" {
      for_each = length(var.break_glass_exempt_arns) > 0 ? [1] : []
      content {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = var.break_glass_exempt_arns
      }
    }
  }
}

data "aws_iam_policy_document" "deny_unencrypted_resources" {
  statement {
    sid       = "DenyUnencryptedS3Bucket"
    effect    = "Deny"
    actions   = ["s3:CreateBucket"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["AES256", "aws:kms"]
    }
  }
  statement {
    sid       = "DenyUnencryptedVolume"
    effect    = "Deny"
    actions   = ["ec2:CreateVolume"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "ec2:Encrypted"
      values   = ["true"]
    }
  }
  statement {
    sid       = "DenyUnencryptedRds"
    effect    = "Deny"
    actions   = ["rds:CreateDBInstance"]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "rds:StorageEncrypted"
      values   = ["true"]
    }
  }
}

data "aws_iam_policy_document" "deny_public_admin_ports" {
  dynamic "statement" {
    for_each = toset([for p in var.admin_ports : tostring(p)])
    content {
      sid       = "DenyPublicPort${statement.value}"
      effect    = "Deny"
      actions   = ["ec2:AuthorizeSecurityGroupIngress"]
      resources = ["*"]
      condition {
        test     = "IpAddressIfExists"
        variable = "ec2:SourceIp"
        values   = ["0.0.0.0/0", "::/0"]
      }
      condition {
        test     = "NumericLessThanEquals"
        variable = "ec2:FromPort"
        values   = [statement.value]
      }
      condition {
        test     = "NumericGreaterThanEquals"
        variable = "ec2:ToPort"
        values   = [statement.value]
      }
    }
  }
}

data "aws_iam_policy_document" "deny_iam_user_inline_policies" {
  statement {
    sid       = "DenyIAMUserInlinePolicies"
    effect    = "Deny"
    actions   = ["iam:PutUserPolicy", "iam:AttachUserPolicy", "iam:CreateUser"]
    resources = ["*"]
    dynamic "condition" {
      for_each = length(var.break_glass_exempt_arns) > 0 ? [1] : []
      content {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = var.break_glass_exempt_arns
      }
    }
  }
}

data "aws_iam_policy_document" "combined" {
  source_policy_documents = [
    data.aws_iam_policy_document.deny_iam_user_creations.json,
    data.aws_iam_policy_document.require_mfa.json,
    data.aws_iam_policy_document.deny_unencrypted_resources.json,
    data.aws_iam_policy_document.deny_public_admin_ports.json,
    data.aws_iam_policy_document.deny_iam_user_inline_policies.json,
  ]
}

resource "aws_organizations_policy" "hardening" {
  count = local.scp_enabled ? 1 : 0

  name        = "${var.name_prefix}-hardening"
  description = "Consolidated HIPAA 164.312 control SCP"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.combined.json
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.scp_enabled ? { for ou in var.ephp_ou_ids : ou => ou } : {}

  policy_id = aws_organizations_policy.hardening[0].id
  target_id = each.key
}
