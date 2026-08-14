output "gitlab_ci_role_arn" {
  description = "ARN of the GitLab CI role."
  value       = try(aws_iam_role.gitlab_ci[0].arn, "")
}

output "oidc_provider_arn" {
  description = "ARN of the GitLab OIDC provider."
  value       = try(aws_iam_openid_connect_provider.gitlab[0].arn, "")
}
