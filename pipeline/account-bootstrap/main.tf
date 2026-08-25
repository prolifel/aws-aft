# The v1 baseline is single-region: the module reads the current provider
# region. Multi-region regional baseline support is a deferred follow-up.
module "account_bootstrap" {
  source = "../../modules/account-bootstrap"

  security_contact_name           = var.security_contact_name
  security_contact_email          = var.security_contact_email
  security_contact_phone          = var.security_contact_phone
  security_contact_title          = var.security_contact_title
  billing_contact_name            = var.billing_contact_name
  billing_contact_email           = var.billing_contact_email
  billing_contact_phone           = var.billing_contact_phone
  billing_contact_title           = var.billing_contact_title
  operations_contact_name         = var.operations_contact_name
  operations_contact_email        = var.operations_contact_email
  operations_contact_phone        = var.operations_contact_phone
  operations_contact_title        = var.operations_contact_title
  jarjit_trust_account_id         = var.jarjit_trust_account_id
  jarjit_role_name                = var.jarjit_role_name
  jarjit_org_id                   = var.jarjit_org_id
  jarjit_cross_account_role_name  = var.jarjit_cross_account_role_name
  break_glass_user_arn            = var.break_glass_user_arn
  break_glass_role_name           = var.break_glass_role_name
  break_glass_policy_name         = var.break_glass_policy_name
  bmc_discovery_user_arn          = var.bmc_discovery_user_arn
  bmc_role_name                   = var.bmc_role_name
  bmc_kms_account_id              = var.bmc_kms_account_id
  terraform_central_role_arn      = var.terraform_central_role_arn
  terraform_local_role_name       = var.terraform_local_role_name
  access_log_bucket_prefix        = var.access_log_bucket_prefix
  terraform_backend_bucket_prefix = var.terraform_backend_bucket_prefix
}

output "bootstrap_outputs" {
  description = "Native baseline resources created by account bootstrap."
  value       = module.account_bootstrap
}
