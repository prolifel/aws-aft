output "kms_key_id" {
  description = "KMS CMK key ID."
  value       = try(aws_kms_key.this[0].id, null)
}

output "kms_key_arn" {
  description = "KMS CMK ARN."
  value       = try(aws_kms_key.this[0].arn, null)
}

output "kms_alias_name" {
  description = "KMS CMK alias name."
  value       = try(aws_kms_alias.this[0].name, null)
}

output "s3_account_public_access_block_id" {
  description = "Account-level S3 public access block resource ID."
  value       = try(aws_s3_account_public_access_block.this[0].id, null)
}
