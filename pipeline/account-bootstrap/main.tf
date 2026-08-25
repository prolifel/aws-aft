# The v1 baseline is single-region: the module reads the current provider
# region. Multi-region regional baseline support is a deferred follow-up.
module "account_bootstrap" {
  source = "../../modules/account-bootstrap"

  security_contact_name      = var.security_contact_name
  security_contact_email     = var.security_contact_email
  security_contact_phone     = var.security_contact_phone
  security_contact_title     = var.security_contact_title
  billing_contact_name       = var.billing_contact_name
  billing_contact_email      = var.billing_contact_email
  billing_contact_phone      = var.billing_contact_phone
  billing_contact_title      = var.billing_contact_title
  operations_contact_name    = var.operations_contact_name
  operations_contact_email   = var.operations_contact_email
  operations_contact_phone   = var.operations_contact_phone
  operations_contact_title   = var.operations_contact_title
  jarjit_trust_account_id    = "000000000000"
  jarjit_org_id              = "o-0000000000"
  break_glass_user_arn       = "arn:aws:iam::000000000000:user/REPLACE_BREAK_GLASS_USER"
  bmc_discovery_user_arn     = "arn:aws:iam::000000000000:user/REPLACE_BMC_USER"
  bmc_kms_account_id         = "000000000000"
  terraform_central_role_arn = "arn:aws:iam::000000000000:role/REPLACE_TERRAFORM_CENTRAL_ROLE"
}

output "bootstrap_outputs" {
  description = "Native baseline resources created by account bootstrap."
  value       = module.account_bootstrap
}
