variable "gitlab_ci_role_arn" {
  description = "ARN of the gitlab-ci role (output of 01-management-init-role-and-hardening)."
  type        = string
  nullable    = false
}
