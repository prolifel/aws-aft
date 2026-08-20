output "scp_policy_id" {
  description = "ID of the consolidated hardening SCP, empty when disabled."
  value       = local.scp_enabled ? aws_organizations_policy.hardening[0].id : ""
}

output "scp_policy_name" {
  description = "Name of the consolidated hardening SCP, empty when disabled."
  value       = local.scp_enabled ? aws_organizations_policy.hardening[0].name : ""
}
