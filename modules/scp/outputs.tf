output "scp_policy_ids" {
  description = "IDs of created SCPs."
  value       = values(aws_organizations_policy.this)[*].id
}

output "scp_policy_names" {
  description = "Names of created SCPs."
  value       = values(aws_organizations_policy.this)[*].name
}
