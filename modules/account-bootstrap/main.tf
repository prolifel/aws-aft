data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
}

resource "aws_iam_account_password_policy" "this" {
  minimum_password_length        = 14
  require_symbols                = true
  require_numbers                = true
  require_uppercase_characters   = true
  require_lowercase_characters   = true
  allow_users_to_change_password = true
  max_password_age               = 90
  password_reuse_prevention      = 24
}

resource "aws_account_alternate_contact" "security" {
  alternate_contact_type = "SECURITY"
  name                   = var.security_contact_name
  title                  = var.security_contact_title
  email_address          = var.security_contact_email
  phone_number           = var.security_contact_phone
}

resource "aws_account_alternate_contact" "billing" {
  alternate_contact_type = "BILLING"
  name                   = var.billing_contact_name
  title                  = var.billing_contact_title
  email_address          = var.billing_contact_email
  phone_number           = var.billing_contact_phone
}

resource "aws_account_alternate_contact" "operations" {
  alternate_contact_type = "OPERATIONS"
  name                   = var.operations_contact_name
  title                  = var.operations_contact_title
  email_address          = var.operations_contact_email
  phone_number           = var.operations_contact_phone
}

data "aws_iam_policy_document" "jarjit_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${var.jarjit_trust_account_id}:root"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalOrgID"
      values   = [var.jarjit_org_id]
    }
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${var.jarjit_trust_account_id}:role/${var.jarjit_role_name}"]
    }
  }
}

resource "aws_iam_role" "jarjit_cross_account" {
  name               = var.jarjit_cross_account_role_name
  assume_role_policy = data.aws_iam_policy_document.jarjit_assume.json

}

resource "aws_s3_bucket" "access_log" {
  bucket = "${var.access_log_bucket_prefix}-${local.account_id}"
}

resource "aws_s3_bucket_lifecycle_configuration" "access_log" {
  bucket = aws_s3_bucket.access_log.id

  rule {
    id     = "TransitionAndExpireLogs"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }

    noncurrent_version_expiration {
      noncurrent_days = 365
    }
  }
}

data "aws_iam_policy_document" "access_log_bucket" {
  statement {
    sid    = "S3LogDeliveryWrite"
    effect = "Allow"
    actions = [
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.access_log.arn}/*"]
    principals {
      type = "Service"
      identifiers = [
        "logging.s3.amazonaws.com",
        "delivery.logs.amazonaws.com",
        "logdelivery.elasticloadbalancing.amazonaws.com",
      ]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "StringEqualsIfExists"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }

  statement {
    sid    = "LogDeliveryAclCheck"
    effect = "Allow"
    actions = [
      "s3:GetBucketAcl",
    ]
    resources = [aws_s3_bucket.access_log.arn]
    principals {
      type        = "Service"
      identifiers = ["delivery.logs.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "RestrictToTLSRequestsOnly"
    effect = "Deny"
    actions = [
      "s3:*",
    ]
    resources = [
      aws_s3_bucket.access_log.arn,
      "${aws_s3_bucket.access_log.arn}/*",
    ]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "access_log" {
  bucket = aws_s3_bucket.access_log.id
  policy = data.aws_iam_policy_document.access_log_bucket.json
}

data "aws_iam_policy_document" "break_glass_admin" {
  statement {
    effect    = "Allow"
    actions   = ["iam:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::${local.account_id}:role/${var.break_glass_role_name}"]
    }
  }
}

resource "aws_iam_policy" "break_glass_admin" {
  name        = var.break_glass_policy_name
  description = "Permission for BreakGlassAdminRole"
  policy      = data.aws_iam_policy_document.break_glass_admin.json
}

data "aws_iam_policy_document" "break_glass_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [var.break_glass_user_arn]
    }
  }
}

resource "aws_iam_role" "break_glass_admin" {
  name               = var.break_glass_role_name
  assume_role_policy = data.aws_iam_policy_document.break_glass_assume.json
  managed_policy_arns = [
    aws_iam_policy.break_glass_admin.arn,
  ]
}

data "aws_iam_policy_document" "glue_catalog_key" {
  statement {
    sid    = "AllowRootAccountFullAccess"
    effect = "Allow"
    actions = [
      "kms:*",
    ]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowGlueServiceUsage"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["glue.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "glue_catalog" {
  description         = "Default Glue CMK key deployed by control tower"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.glue_catalog_key.json
}

resource "aws_kms_alias" "glue_catalog" {
  name          = "alias/default-glue-datacatalog-cmk"
  target_key_id = aws_kms_key.glue_catalog.key_id
}

resource "aws_glue_data_catalog_encryption_settings" "this" {
  catalog_id = local.account_id

  data_catalog_encryption_settings {
    encryption_at_rest {
      catalog_encryption_mode = "SSE-KMS"
      sse_aws_kms_key_id      = aws_kms_key.glue_catalog.arn
    }
    connection_password_encryption {
      return_connection_password_encrypted = false
    }
  }
}

resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

resource "aws_ebs_default_kms_key" "this" {
  key_arn = "arn:aws:kms:${local.region}:${local.account_id}:alias/aws/ebs"
}

data "aws_iam_policy_document" "bmc_additional" {
  statement {
    effect = "Allow"
    actions = [
      "lakeformation:List*",
      "sdb:DomainMetadata",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bmc_additional" {
  name        = "bmcDiscoveryAdditionalROScanPolicy"
  description = "Additional Permission for BMC"
  policy      = data.aws_iam_policy_document.bmc_additional.json
}

data "aws_iam_policy_document" "bmc_kms" {
  statement {
    sid    = "AllowKMSAccess"
    effect = "Allow"
    actions = [
      "kms:GetPublicKey",
      "kms:Decrypt",
      "kms:GetKeyPolicy",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:Verify",
      "kms:GenerateDataKeyPairWithoutPlaintext",
      "kms:GenerateDataKeyPair",
      "kms:ReEncryptFrom",
      "kms:GetParametersForImport",
      "kms:Encrypt",
      "kms:GetKeyRotationStatus",
      "kms:GenerateDataKey",
      "kms:ReEncryptTo",
      "kms:DescribeKey",
      "kms:Sign",
    ]
    resources = [
      "arn:aws:kms:*:${local.account_id}:key/*",
      "arn:aws:kms:*:${var.bmc_kms_account_id}:key/*",
    ]
  }

  statement {
    sid    = "AllowKMSGenerateRandom"
    effect = "Allow"
    actions = [
      "kms:GenerateRandom",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bmc_kms" {
  name        = "bmcDiscoveryKMSPermissionPolicy"
  description = "KMS Permission for BMC"
  policy      = data.aws_iam_policy_document.bmc_kms.json
}

data "aws_iam_policy_document" "bmc_session_manager" {
  statement {
    sid    = "EnableSSMSession"
    effect = "Allow"
    actions = [
      "ssm:StartSession",
    ]
    resources = [
      "arn:aws:ssm:*:*:document/SSM-SessionManagerRunShell",
      "arn:aws:ssm:*:*:document/AWS-StartNonInteractiveCommand",
      "arn:aws:ec2:*:*:instance/*",
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:ResumeSession",
      "ssm:TerminateSession",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstances",
      "ssm:DescribeInstanceInformation",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "bmc_session_manager" {
  name        = "bmcDiscoverySessionManagerScanPolicy"
  description = "Session Manager Permission for BMC"
  policy      = data.aws_iam_policy_document.bmc_session_manager.json
}

data "aws_iam_policy_document" "bmc_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = [var.bmc_discovery_user_arn]
    }
  }
}

resource "aws_iam_role" "bmc_discovery" {
  name               = var.bmc_role_name
  assume_role_policy = data.aws_iam_policy_document.bmc_assume.json
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
    aws_iam_policy.bmc_additional.arn,
    aws_iam_policy.bmc_kms.arn,
    aws_iam_policy.bmc_session_manager.arn,
  ]
}

resource "aws_kms_key" "terraform_backend" {
  description         = "KMS key for terraform backend"
  enable_key_rotation = true
}

resource "aws_kms_alias" "terraform_backend" {
  name          = "alias/terraform-backend-kms"
  target_key_id = aws_kms_key.terraform_backend.key_id
}

resource "aws_s3_bucket" "terraform_backend" {
  bucket = "${var.terraform_backend_bucket_prefix}-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "terraform_backend" {
  bucket = aws_s3_bucket.terraform_backend.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_backend" {
  bucket = aws_s3_bucket.terraform_backend.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.terraform_backend.arn
    }
  }
}

resource "aws_s3_bucket_logging" "terraform_backend" {
  bucket = aws_s3_bucket.terraform_backend.id

  target_bucket = aws_s3_bucket.access_log.id
  target_prefix = "${local.account_id}/terraform-backend-s3-${local.account_id}/"
}

resource "aws_s3_bucket_lifecycle_configuration" "terraform_backend" {
  bucket = aws_s3_bucket.terraform_backend.id

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "terraform_backend_bucket" {
  statement {
    sid    = "AllowCTAndTFAccess"
    effect = "Allow"
    actions = [
      "s3:*",
    ]
    resources = ["${aws_s3_bucket.terraform_backend.arn}/*"]
    principals {
      type = "AWS"
      identifiers = [
        "arn:aws:iam::${local.account_id}:role/AWSControlTowerExecution",
        "arn:aws:iam::${local.account_id}:role/${var.terraform_local_role_name}",
      ]
    }
  }

  statement {
    sid    = "RestrictToTLSRequestsOnly"
    effect = "Deny"
    actions = [
      "s3:*",
    ]
    resources = ["${aws_s3_bucket.terraform_backend.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "terraform_backend" {
  bucket = aws_s3_bucket.terraform_backend.id
  policy = data.aws_iam_policy_document.terraform_backend_bucket.json
}

data "aws_iam_policy_document" "terraform_local_assume" {
  statement {
    sid     = "AllowTerraformCentral"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [var.terraform_central_role_arn]
    }
  }
}

resource "aws_iam_role" "terraform_local" {
  name               = var.terraform_local_role_name
  assume_role_policy = data.aws_iam_policy_document.terraform_local_assume.json
  managed_policy_arns = [
    aws_iam_policy.terraform_iam_access.arn,
    aws_iam_policy.terraform_backend_access.arn,
    "arn:aws:iam::aws:policy/PowerUserAccess",
  ]
}

data "aws_iam_policy_document" "terraform_iam_access" {
  statement {
    sid    = "AllowManageIAMAccountSettings"
    effect = "Allow"
    actions = [
      "iam:UpdateAccountPasswordPolicy",
      "iam:GetAccountPasswordPolicy",
      "iam:DeleteAccountPasswordPolicy",
      "iam:CreateAccountAlias",
      "iam:DeleteAccountAlias",
      "iam:ListAccountAliases",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowManageInstanceProfileOidcSamlRoleAnywhere"
    effect = "Allow"
    actions = [
      "iam:ListInstanceProfiles",
      "iam:ListInstanceProfilesForRole",
      "iam:ListInstanceProfileTags",
      "iam:GetInstanceProfile",
      "iam:AddRoleToInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
      "iam:ListOpenIDConnectProviders",
      "iam:ListOpenIDConnectProviderTags",
      "iam:GetOpenIDConnectProvider",
      "iam:CreateOpenIDConnectProvider",
      "iam:AddClientIDToOpenIDConnectProvider",
      "iam:DeleteOpenIDConnectProvider",
      "iam:RemoveClientIDFromOpenIDConnectProvider",
      "iam:UpdateOpenIDConnectProviderThumbprint",
      "iam:TagOpenIDConnectProvider",
      "iam:UntagOpenIDConnectProvider",
      "iam:ListSAMLProviders",
      "iam:ListSAMLProviderTags",
      "iam:GetSAMLProvider",
      "iam:DeleteSAMLProvider",
      "iam:UpdateSAMLProvider",
      "iam:TagSAMLProvider",
      "iam:UntagSAMLProvider",
      "rolesanywhere:*",
      "sso:CreateAccountAssignment",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowManageRoles"
    effect = "Allow"
    actions = [
      "iam:TagRole",
      "iam:UntagRole",
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:UpdateRole",
      "iam:ListRolePolicies",
      "iam:ListRoleTags",
      "iam:ListRoles",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "AllowManageCustomPolicies"
    effect = "Allow"
    actions = [
      "iam:ListPolicies",
      "iam:GetPolicyVersion",
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:ListEntitiesForPolicy",
      "iam:GetPolicy",
      "iam:ListPolicyVersions",
      "iam:TagPolicy",
      "iam:UntagPolicy",
    ]
    resources = [
      "arn:aws:iam::${local.account_id}:policy/*",
      "arn:aws:iam::aws:policy/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "DenyAttachDetachPermissivePolicy"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
    ]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:ArnLike"
      variable = "iam:PolicyARN"
      values = [
        "arn:aws:iam::aws:policy/*AdministratorAccess*",
        "arn:aws:iam::aws:policy/*PowerUser*",
        "arn:aws:iam::aws:policy/*FullAccess*",
      ]
    }
  }

  statement {
    sid    = "DenyTerraformIamRoleAccess"
    effect = "Deny"
    actions = [
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
    ]
    resources = ["arn:aws:iam::${local.account_id}:role/${var.terraform_local_role_name}"]
  }

  statement {
    sid    = "DenyTerraformIamPolicyAccess"
    effect = "Deny"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:GetPolicy",
      "iam:ListPolicyVersions",
      "iam:GetPolicyVersion",
    ]
    resources = ["arn:aws:iam::${local.account_id}:policy/terraform-iam-access-policy"]
  }

  statement {
    sid    = "AllowSSOPermissionSetManagement"
    effect = "Allow"
    actions = [
      "sso:PutInlinePolicyToPermissionSet",
      "sso:DeleteInlinePolicyFromPermissionSet",
      "sso:GetInlinePolicyForPermissionSet",
      "sso:AttachManagedPolicyToPermissionSet",
      "sso:DetachManagedPolicyFromPermissionSet",
      "sso:ListManagedPoliciesInPermissionSet",
      "sso:CreatePermissionSet",
      "sso:DeletePermissionSet",
      "sso:DescribePermissionSet",
      "sso:UpdatePermissionSet",
      "sso:CreateAccountAssignment",
      "sso:DeleteAccountAssignment",
      "sso:DescribeAccountAssignmentCreationStatus",
      "sso:DescribeAccountAssignmentDeletionStatus",
      "sso:ListAccountAssignments",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "terraform_iam_access" {
  name        = "terraform-iam-access-policy"
  description = "Policy for terraform local role to manage iam role only"
  policy      = data.aws_iam_policy_document.terraform_iam_access.json
}

data "aws_iam_policy_document" "terraform_backend_access" {
  statement {
    sid    = "AllowTerraformRoleUseOfKMS"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:DescribeKey",
      "kms:ListAliases",
    ]
    resources = [aws_kms_key.terraform_backend.arn]
  }

  statement {
    sid    = "DenyDetachTerraformBackendPolicy"
    effect = "Deny"
    actions = [
      "iam:DetachRolePolicy",
      "iam:DetachUserPolicy",
      "iam:DetachGroupPolicy",
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["arn:aws:iam::${local.account_id}:policy/terraform-backend-access-policy"]
    }
  }

  statement {
    sid    = "DenyTerraformBackendPolicyAccess"
    effect = "Deny"
    actions = [
      "iam:CreatePolicy",
      "iam:DeletePolicy",
      "iam:CreatePolicyVersion",
      "iam:DeletePolicyVersion",
      "iam:SetDefaultPolicyVersion",
      "iam:GetPolicy",
      "iam:ListPolicyVersions",
      "iam:GetPolicyVersion",
    ]
    resources = ["arn:aws:iam::${local.account_id}:policy/terraform-backend-access-policy"]
  }

  statement {
    sid    = "AllowTerraformBackendObjectAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.terraform_backend.arn}/*"]
  }

  statement {
    sid    = "AllowTerraformBackendListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
    ]
    resources = [aws_s3_bucket.terraform_backend.arn]
  }

  statement {
    sid    = "AllowListAllBucket"
    effect = "Allow"
    actions = [
      "s3:ListAllMyBuckets",
    ]
    resources = ["arn:aws:s3:::*"]
  }
}

resource "aws_iam_policy" "terraform_backend_access" {
  name        = "terraform-backend-access-policy"
  description = "Policy for accessing terraform backend"
  policy      = data.aws_iam_policy_document.terraform_backend_access.json
}

data "aws_iam_policy_document" "jarjit_cloudtrail" {
  statement {
    effect = "Allow"
    actions = [
      "cloudtrail:LookupEvents",
      "cloudtrail:GetEventSelectors",
      "cloudtrail:DescribeTrails",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "jarjit_cloudtrail" {
  name   = "CloudTrailAccessPolicy"
  role   = aws_iam_role.jarjit_cross_account.id
  policy = data.aws_iam_policy_document.jarjit_cloudtrail.json
}
