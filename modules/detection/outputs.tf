output "guardduty_detector_id" {
  description = "GuardDuty detector ID."
  value       = try(aws_guardduty_detector.this[0].id, try(aws_guardduty_detector.org[0].id, ""))
}

output "guardduty_org_admin_account_id" {
  description = "GuardDuty delegated admin account ID."
  value       = try(aws_guardduty_organization_admin_account.this[0].id, "")
}

output "securityhub_enabled" {
  description = "Whether SecurityHub is enabled."
  value       = try(aws_securityhub_account.this[0].id != "", false) || try(aws_securityhub_account.org[0].id != "", false)
}

output "macie_classification_job_id" {
  description = "Macie classification job ID."
  value       = try(aws_macie2_classification_job.this[0].id, "")
}
