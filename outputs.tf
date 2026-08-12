output "s3_account_public_access_block_id" {
  description = "Account-level S3 public access block resource ID."
  value       = try(aws_s3_account_public_access_block.this[0].id, null)
}

output "iam_password_policy_id" {
  description = "IAM account password policy resource ID."
  value       = try(aws_iam_account_password_policy.strict[0].id, null)
}

output "guardduty_detector_id" {
  description = "GuardDuty detector ID."
  value       = try(aws_guardduty_detector.this[0].id, null)
}

output "cloudtrail_id" {
  description = "CloudTrail trail ARN."
  value       = try(aws_cloudtrail.this[0].arn, null)
}

output "cloudtrail_bucket_arn" {
  description = "CloudTrail log bucket ARN."
  value       = try(aws_s3_bucket.cloudtrail[0].arn, null)
}

output "cloudtrail_kms_key_arn" {
  description = "KMS key used to encrypt CloudTrail logs."
  value       = try(aws_kms_key.cloudtrail[0].arn, null)
}

output "default_security_group_ids" {
  description = "IDs of default security groups that had rules removed."
  value       = aws_default_security_group.this[*].id
}
