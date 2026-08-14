variable "gitlab_ci_role_arn" {
  description = "ARN of the gitlab-ci role in the management account that must be able to assume the per-account role."
  type        = string
  nullable    = false
}

variable "role_name" {
  description = "Name of the per-account deploy role."
  type        = string
  default     = "hardened-deploy"
}
