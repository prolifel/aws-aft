module "account_vending" {
  source = "../../modules/account-vending"

  account_name               = var.account_name
  email                      = var.email
  managed_org_unit           = var.managed_org_unit
  account_tags               = var.account_tags
  product_name               = var.product_name
  sso_user_email             = var.sso_user_email
  sso_user_first_name        = var.sso_user_first_name
  sso_user_last_name         = var.sso_user_last_name
  account_factory_product_id = var.account_factory_product_id
}

output "provisioned_account_id" {
  description = "AWS account ID of the provisioned account."
  value       = module.account_vending.provisioned_account_id
}

output "account_key" {
  description = "Stable key identifying this vended account (account_name)."
  value       = var.account_name
}
