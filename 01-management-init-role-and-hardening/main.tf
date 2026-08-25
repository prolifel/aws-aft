module "ci" {
  source = "../modules/ci"

  management_account  = true
  name_prefix         = var.name_prefix
  region              = var.region
  gitlab_url          = var.gitlab_url
  gitlab_project_path = var.gitlab_project_path
  state_bucket_arn    = var.state_bucket_arn
}
