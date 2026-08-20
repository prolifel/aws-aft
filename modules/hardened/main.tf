data "aws_caller_identity" "current" {}

data "aws_organizations_organization" "org" {
  count = var.management_account ? 1 : 0
}

locals {
  child_account_ids = var.management_account ? [
    for a in data.aws_organizations_organization.org[0].accounts :
    a.id
    if a.id != data.aws_caller_identity.current.account_id
  ] : []
  mgmt_break_glass_role_arn = var.management_account ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.break_glass_role_name}" : var.break_glass_mgmt_role_arn
  break_glass_exempt_arns   = var.management_account ? concat([for id in local.child_account_ids : "arn:aws:iam::${id}:role/${var.break_glass_role_name}"], [local.mgmt_break_glass_role_arn]) : []
}

module "encryption" {
  source = "../encryption"

  enabled                        = var.encryption_enabled
  name_prefix                    = var.name_prefix
  tags                           = var.tags
  kms_admin_arns                 = var.kms_admin_arns
  kms_user_arns                  = var.kms_user_arns
  s3_account_public_access_block = var.s3_account_public_access_block
  ebs_encryption_enabled         = var.ebs_encryption_enabled
}

module "identity" {
  source = "../identity"

  enabled                        = var.identity_enabled
  management_account             = var.management_account
  name_prefix                    = var.name_prefix
  tags                           = var.tags
  sso_permission_sets            = var.sso_permission_sets
  sso_group_arns                 = var.sso_group_arns
  sso_target_account_id          = var.sso_target_account_id
  iam_password_policy            = var.iam_password_policy
  break_glass_role_name          = var.break_glass_role_name
  break_glass_user_name          = var.break_glass_user_name
  break_glass_mgmt_role_arn      = local.mgmt_break_glass_role_arn
  break_glass_target_account_ids = local.child_account_ids
}

module "scp" {
  source = "../scp"

  enabled                 = var.scp_enabled
  management_account      = var.management_account
  name_prefix             = var.name_prefix
  ephp_ou_ids             = var.ephp_ou_ids
  break_glass_exempt_arns = local.break_glass_exempt_arns
}

module "audit" {
  source = "../audit"

  enabled                    = var.audit_enabled
  management_account         = var.management_account
  name_prefix                = var.name_prefix
  region                     = var.region
  tags                       = var.tags
  log_bucket_name            = var.log_bucket_name
  log_bucket_arn             = var.log_bucket_arn
  object_lock_retention_days = var.object_lock_retention_days
  allowed_log_account_ids    = var.allowed_log_account_ids
  config_rules               = var.config_rules
  config_rule_parameters     = var.config_rule_parameters
}

module "detection" {
  source = "../detection"

  providers = {
    aws                 = aws
    aws.delegated_admin = aws.delegated_admin
  }

  enabled                           = var.detection_enabled
  management_account                = var.management_account
  name_prefix                       = var.name_prefix
  tags                              = var.tags
  guardduty_admin_account_id        = var.guardduty_admin_account_id
  securityhub_admin_account_id      = var.securityhub_admin_account_id
  inspector_admin_account_id        = var.inspector_admin_account_id
  macie_admin_account_id            = var.macie_admin_account_id
  securityhub_standards             = var.securityhub_standards
  malware_protection_s3_bucket_arns = var.malware_protection_s3_bucket_arns
  macie_s3_bucket_arns              = var.macie_s3_bucket_arns
}

module "ci" {
  source = "../ci"

  enabled             = var.ci_enabled
  management_account  = var.management_account
  name_prefix         = var.name_prefix
  tags                = var.tags
  gitlab_url          = var.gitlab_url
  gitlab_project_path = var.gitlab_project_path
  gitlab_branch       = var.gitlab_branch
  oidc_thumbprint     = var.oidc_thumbprint
  config_bucket_arn   = var.config_bucket_arn
}
