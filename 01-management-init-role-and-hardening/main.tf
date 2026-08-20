module "hardened" {
  source = "../modules/hardened"

  providers = {
    aws                 = aws
    aws.delegated_admin = aws.delegated_admin
  }

  management_account           = true
  ci_enabled                   = true
  name_prefix                  = var.name_prefix
  region                       = var.region
  tags                         = var.tags
  gitlab_url                   = var.gitlab_url
  gitlab_project_path          = var.gitlab_project_path
  config_bucket_arn            = "arn:aws:s3:::${aws_s3_bucket.config.bucket}"
  ephp_ou_ids                  = var.ephp_ou_ids
  break_glass_user_name        = var.break_glass_user_name
  sso_target_account_id        = var.sso_target_account_id
  guardduty_admin_account_id   = var.guardduty_admin_account_id
  securityhub_admin_account_id = var.securityhub_admin_account_id
  inspector_admin_account_id   = var.inspector_admin_account_id
  macie_admin_account_id       = var.macie_admin_account_id
}

data "aws_organizations_organization" "org" {}

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

resource "aws_organizations_organization" "org" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "controltower.amazonaws.com",
    "guardduty.amazonaws.com",
    "inspector2.amazonaws.com",
    "macie.amazonaws.com",
    "member.org.stacksets.cloudformation.amazonaws.com",
    "securityhub.amazonaws.com",
    "sso.amazonaws.com"
  ]
  enabled_policy_types     = ["SERVICE_CONTROL_POLICY"]
  feature_set              = "ALL"
  return_organization_only = null
}

resource "aws_s3_bucket" "config" {
  bucket        = "aws-hardened-config-${local.account_id}-${var.region}"
  force_destroy = false
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config.json
}

data "aws_iam_policy_document" "config" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.config.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [for a in data.aws_organizations_organization.org.accounts : "arn:aws:iam::${a.id}:root"]
    }
  }
}

resource "aws_s3_object" "config" {
  bucket = aws_s3_bucket.config.id
  key    = "config.json"
  content = jsonencode({
    log_bucket_name            = module.hardened.log_bucket_id
    log_bucket_arn             = module.hardened.log_bucket_arn
    break_glass_mgmt_role_arn  = module.hardened.break_glass_role_arn
    guardduty_admin_account_id = var.guardduty_admin_account_id
    inspector_admin_account_id = var.inspector_admin_account_id
    macie_admin_account_id     = var.macie_admin_account_id
  })
}
