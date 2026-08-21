output "kms_key_id" {
  description = "KMS CMK key ID."
  value       = module.encryption.kms_key_id
}

output "kms_key_arn" {
  description = "KMS CMK ARN."
  value       = module.encryption.kms_key_arn
}

output "s3_account_public_access_block_id" {
  description = "Account-level S3 public access block resource ID."
  value       = module.encryption.s3_account_public_access_block_id
}

output "sso_permission_set_names" {
  description = "Names of created SSO permission sets."
  value       = module.identity.sso_permission_set_names
}

output "sso_permission_set_arns" {
  description = "ARNs of created SSO permission sets."
  value       = module.identity.sso_permission_set_arns
}

output "break_glass_role_name" {
  description = "Name of the break-glass role."
  value       = module.identity.break_glass_role_name
}

output "break_glass_role_arn" {
  description = "ARN of the break-glass role."
  value       = module.identity.break_glass_role_arn
}

output "break_glass_sns_topic_arn" {
  description = "SNS topic ARN for break-glass alerts."
  value       = module.identity.break_glass_sns_topic_arn
}

output "break_glass_user_name" {
  description = "Name of the management-account break-glass IAM user."
  value       = module.identity.break_glass_user_name
}

output "scp_policy_id" {
  description = "ID of the consolidated hardening SCP."
  value       = module.scp.scp_policy_id
}

output "scp_policy_name" {
  description = "Name of the consolidated hardening SCP."
  value       = module.scp.scp_policy_name
}

# note: cloudtrail org enabled via control tower
output "log_bucket_id" {
  description = "Log bucket name."
  value       = module.audit.log_bucket_id
}

output "log_bucket_arn" {
  description = "Log bucket ARN."
  value       = module.audit.log_bucket_arn
}

output "log_bucket_kms_key_arn" {
  description = "KMS key ARN for the log bucket."
  value       = module.audit.log_bucket_kms_key_arn
}

output "config_recorder_id" {
  description = "Config recorder name."
  value       = module.audit.config_recorder_id
}

output "config_rule_names" {
  description = "Names of deployed Config rules."
  value       = module.audit.config_rule_names
}

output "conformance_pack_name" {
  description = "Name of the HIPAA conformance pack."
  value       = module.audit.conformance_pack_name
}

output "remediation_rule_names" {
  description = "Names of rules with attached remediation."
  value       = module.audit.remediation_rule_names
}

output "custom_remediation_doc_name" {
  description = "Name of the custom admin-port ingress remediation document."
  value       = module.audit.custom_remediation_doc_name
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID."
  value       = module.detection.guardduty_detector_id
}

output "guardduty_org_admin_account_id" {
  description = "GuardDuty delegated admin account ID."
  value       = module.detection.guardduty_org_admin_account_id
}

output "securityhub_enabled" {
  description = "Whether SecurityHub is enabled."
  value       = module.detection.securityhub_enabled
}

output "macie_classification_job_id" {
  description = "Macie classification job ID."
  value       = module.detection.macie_classification_job_id
}

output "gitlab_ci_role_arn" {
  description = "ARN of the GitLab CI role."
  value       = module.ci.gitlab_ci_role_arn
}
