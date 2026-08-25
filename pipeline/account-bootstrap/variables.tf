variable "security_contact_name" {
  description = "Name of the security alternate contact."
  type        = string
  nullable    = false
}
variable "security_contact_email" {
  description = "Email of the security alternate contact."
  type        = string
  nullable    = false
}
variable "security_contact_phone" {
  description = "Phone of the security alternate contact."
  type        = string
  nullable    = false
}
variable "security_contact_title" {
  description = "Title of the security alternate contact."
  type        = string
  default     = "Cloud Security Team"
}
variable "billing_contact_name" {
  description = "Name of the billing alternate contact."
  type        = string
  nullable    = false
}
variable "billing_contact_email" {
  description = "Email of the billing alternate contact."
  type        = string
  nullable    = false
}
variable "billing_contact_phone" {
  description = "Phone of the billing alternate contact."
  type        = string
  nullable    = false
}
variable "billing_contact_title" {
  description = "Title of the billing alternate contact."
  type        = string
  default     = "Cloud FinOps Team"
}
variable "operations_contact_name" {
  description = "Name of the operations alternate contact."
  type        = string
  nullable    = false
}
variable "operations_contact_email" {
  description = "Email of the operations alternate contact."
  type        = string
  nullable    = false
}
variable "operations_contact_phone" {
  description = "Phone of the operations alternate contact."
  type        = string
  nullable    = false
}
variable "operations_contact_title" {
  description = "Title of the operations alternate contact."
  type        = string
  default     = "Cloud Platform Engineering Team"
}
variable "jarjit_trust_account_id" {
  description = "AWS account ID trusted to assume the Jarjit cross-account role."
  type        = string
  nullable    = false
}
variable "jarjit_role_name" {
  description = "Role name trusted to assume the Jarjit cross-account role."
  type        = string
  default     = "jarjit-role"
}
variable "jarjit_org_id" {
  description = "AWS organization ID that constrains the Jarjit trust condition."
  type        = string
  nullable    = false
}
variable "jarjit_cross_account_role_name" {
  description = "Name of the Jarjit cross-account role."
  type        = string
  default     = "JarjitCrossAccountRole"
}
variable "break_glass_user_arn" {
  description = "ARN of the IAM user allowed to assume the break-glass role."
  type        = string
  nullable    = false
}
variable "break_glass_role_name" {
  description = "Name of the break-glass admin role."
  type        = string
  default     = "BreakGlassAdminRole"
}
variable "break_glass_policy_name" {
  description = "Name of the break-glass admin managed policy."
  type        = string
  default     = "BreakGlassAdminPolicy"
}
variable "bmc_discovery_user_arn" {
  description = "ARN of the IAM user trusted to assume the BMC discovery role."
  type        = string
  nullable    = false
}
variable "bmc_role_name" {
  description = "Name of the BMC discovery read-only role."
  type        = string
  default     = "bmcDiscoveryROScanTrustRole"
}
variable "bmc_kms_account_id" {
  description = "Additional AWS account ID whose KMS keys the BMC role may read."
  type        = string
  nullable    = false
}
variable "terraform_central_role_arn" {
  description = "ARN of the central role trusted to assume the terraform-local role."
  type        = string
  nullable    = false
}
variable "terraform_local_role_name" {
  description = "Name of the bootstrap-only terraform-local role."
  type        = string
  default     = "terraform-local"
}
variable "access_log_bucket_prefix" {
  description = "Prefix for the S3 access-log bucket name."
  type        = string
  default     = "cimb-s3-access-logs"
}
variable "terraform_backend_bucket_prefix" {
  description = "Prefix for the per-account Terraform backend bucket name."
  type        = string
  default     = "terraform-backend-s3"
}
variable "region" {
  description = "AWS region for the single-region baseline provider."
  type        = string
  default     = "ap-southeast-3"
}
