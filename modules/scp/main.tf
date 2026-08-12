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
      for_each = var.break_glass_role_arn != "" ? [1] : []
      content {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = [var.break_glass_role_arn]
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
      for_each = var.break_glass_role_arn != "" ? [1] : []
      content {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = [var.break_glass_role_arn]
      }
    }
  }
}

locals {
  scp_policies = {
    DenyIAMUserCreations      = data.aws_iam_policy_document.deny_iam_user_creations.json
    RequireMFA                = data.aws_iam_policy_document.require_mfa.json
    DenyUnencryptedResources  = data.aws_iam_policy_document.deny_unencrypted_resources.json
    DenyPublicAdminPorts      = data.aws_iam_policy_document.deny_public_admin_ports.json
    DenyIAMUserInlinePolicies = data.aws_iam_policy_document.deny_iam_user_inline_policies.json
  }

  scp_attachments = merge([
    for scp_name, policy_id in aws_organizations_policy.this : {
      for ou in var.ephp_ou_ids : "${scp_name}:${ou}" => {
        policy_id = policy_id.id
        ou_id     = ou
      }
    }
  ]...)
}

resource "aws_organizations_policy" "this" {
  for_each = local.scp_enabled ? local.scp_policies : {}

  name        = "${var.name_prefix}-${each.key}"
  description = "HIPAA 164.312 control: ${each.key}"
  type        = "SERVICE_CONTROL_POLICY"
  content     = each.value

  tags = {
    Control = each.key
  }
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.scp_enabled ? local.scp_attachments : {}

  policy_id = each.value.policy_id
  target_id = each.value.ou_id
}
