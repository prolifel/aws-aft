output "gitlab_ci_role_arn" {
  description = "ARN of the gitlab-ci role. Set this as the CI_ROLE_ARN GitLab variable."
  value       = module.hardened.gitlab_ci_role_arn
}

output "state_bucket_name" {
  description = "Name of the handoff config bucket."
  value       = aws_s3_bucket.config.id
}
