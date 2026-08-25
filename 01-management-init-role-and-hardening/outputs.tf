output "gitlab_ci_role_arn" {
  description = "ARN of the GitLab CI role; configure it as CI_ROLE_ARN."
  value       = module.ci.gitlab_ci_role_arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitLab OIDC provider."
  value       = module.ci.oidc_provider_arn
}
