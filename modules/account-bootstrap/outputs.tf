output "bmc_role_arn" {
  description = "ARN of the BMC discovery role."
  value       = aws_iam_role.bmc_discovery.arn
}

output "terraform_local_role_arn" {
  description = "ARN of the terraform-local role."
  value       = aws_iam_role.terraform_local.arn
}

output "terraform_backend_bucket" {
  description = "Name of the per-account Terraform backend bucket."
  value       = aws_s3_bucket.terraform_backend.id
}

output "break_glass_role_arn" {
  description = "ARN of the break-glass admin role."
  value       = aws_iam_role.break_glass_admin.arn
}

output "jarjit_cross_account_role_arn" {
  description = "ARN of the Jarjit cross-account role."
  value       = aws_iam_role.jarjit_cross_account.arn
}
