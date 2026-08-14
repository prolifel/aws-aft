variable "enabled" {
  description = "Whether to create GitLab CI OIDC resources."
  type        = bool
  default     = true
}

variable "management_account" {
  description = "Whether this module runs in the organization management account."
  type        = bool
}

variable "name_prefix" {
  description = "Prefix for the GitLab CI role name."
  type        = string
}

variable "tags" {
  description = "Tags applied to the GitLab CI role."
  type        = map(string)
  default     = {}
}

variable "gitlab_url" {
  description = "GitLab OIDC issuer base URL, e.g. https://gitlab.example.com."
  type        = string
  nullable    = false
}

variable "gitlab_project_path" {
  description = "GitLab project path for the OIDC sub trust condition, e.g. prolifel/aws-aft."
  type        = string
  nullable    = false
}

variable "gitlab_branch" {
  description = "Branch allowed to assume the GitLab CI role."
  type        = string
  default     = "main"
}

variable "oidc_thumbprint" {
  description = "Optional SHA-1 thumbprint of the OIDC issuer cert. Empty lets AWS auto-fetch."
  type        = string
  default     = null
}

variable "deploy_role_name" {
  description = "Per-account role name the GitLab CI role may assume."
  type        = string
  default     = "hardened-deploy"
}

variable "config_bucket_arn" {
  description = "ARN of the handoff config bucket. Empty skips the s3:GetObject policy."
  type        = string
  default     = ""
}
