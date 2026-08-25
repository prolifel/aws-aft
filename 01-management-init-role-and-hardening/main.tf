module "ci" {
  source = "../modules/ci"

  enabled             = true
  management_account  = true
  name_prefix         = var.name_prefix
  region              = var.region
  tags                = var.tags
  gitlab_url          = var.gitlab_url
  gitlab_branch       = var.gitlab_branch
  gitlab_project_path = var.gitlab_project_path
  oidc_thumbprint     = var.oidc_thumbprint
  state_bucket_arn    = var.state_bucket_arn
  state_kms_key_arn   = var.state_kms_key_arn
}
