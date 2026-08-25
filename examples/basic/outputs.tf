output "terraform_backend_bucket" {
  description = "Per-account Terraform backend created by the baseline."
  value       = module.account_bootstrap.terraform_backend_bucket
}
