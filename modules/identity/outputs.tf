output "sso_permission_set_names" {
  description = "Names of created SSO permission sets."
  value       = keys(aws_ssoadmin_permission_set.this)
}

output "sso_permission_set_arns" {
  description = "ARNs of created SSO permission sets."
  value       = values(aws_ssoadmin_permission_set.this)[*].arn
}

output "break_glass_role_name" {
  description = "Name of the break-glass role."
  value       = try(aws_iam_role.break_glass[0].name, "")
}

output "break_glass_role_arn" {
  description = "ARN of the break-glass role."
  value       = try(aws_iam_role.break_glass[0].arn, "")
}

output "break_glass_sns_topic_arn" {
  description = "SNS topic ARN for break-glass alerts."
  value       = try(aws_sns_topic.break_glass[0].arn, "")
}

output "break_glass_user_name" {
  description = "Name of the management-account break-glass IAM user."
  value       = try(aws_iam_user.break_glass[0].name, "")
}

output "break_glass_role_trust_policy" {
  description = "Assume-role policy JSON of the break-glass role (test support)."
  value       = try(aws_iam_role.break_glass[0].assume_role_policy, "")
}

output "break_glass_role_policy" {
  description = "Inline policy JSON of the child-account break-glass role (test support)."
  value       = try(aws_iam_role_policy.break_glass[0].policy, "")
}

output "break_glass_mgmt_role_policy" {
  description = "Inline policy JSON of the management-account break-glass role (test support)."
  value       = try(aws_iam_role_policy.break_glass_mgmt[0].policy, "")
}
