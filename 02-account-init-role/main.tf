module "account_init_role" {
  source = "../modules/account-init-role"

  gitlab_ci_role_arn = var.gitlab_ci_role_arn
}
