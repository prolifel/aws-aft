# note: cloudtrail org enabled via control tower

output "log_bucket_id" {
  description = "Log bucket name."
  value       = var.enabled && var.management_account ? aws_s3_bucket.logs[0].id : (var.log_bucket_name != "" ? var.log_bucket_name : "")
}

output "log_bucket_arn" {
  description = "Log bucket ARN."
  value       = var.enabled && var.management_account ? aws_s3_bucket.logs[0].arn : var.log_bucket_arn
}

output "log_bucket_kms_key_arn" {
  description = "KMS key ARN for the log bucket."
  value       = try(aws_kms_key.logs[0].arn, "")
}

output "config_recorder_id" {
  description = "Config recorder name."
  value       = try(aws_config_configuration_recorder.this[0].id, "")
}

output "config_rule_names" {
  description = "Names of deployed Config rules."
  value       = keys(aws_config_config_rule.managed)
}

output "conformance_pack_name" {
  description = "Name of the HIPAA conformance pack."
  value       = try(aws_config_conformance_pack.hipaa[0].name, "")
}

output "remediation_rule_names" {
  description = "Names of rules with attached remediation."
  value       = var.enabled && !var.management_account ? concat(keys(local.remediation_entries), local.restricted_ingress_remediation ? ["RESTRICTED_INCOMING_TRAFFIC"] : []) : []
}

output "custom_remediation_doc_name" {
  description = "Name of the custom admin-port ingress remediation document."
  value       = var.enabled && !var.management_account ? aws_ssm_document.remediation_swap_public_admin_ingress[0].name : ""
}
