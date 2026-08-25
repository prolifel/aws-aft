variable "enabled" {
  description = "Whether to create GitLab CI OIDC resources."
  type        = bool
  default     = true
}

variable "management_account" {
  description = "Whether this module runs in the Control Tower management account."
  type        = bool
}

variable "name_prefix" {
  description = "Prefix for the GitLab CI role name."
  type        = string
}

variable "region" {
  description = "AWS region for management-plane resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to the GitLab CI role."
  type        = map(string)
  default     = {}
}

variable "gitlab_url" {
  description = "GitLab OIDC issuer base URL."
  type        = string
  nullable    = false
}

variable "gitlab_project_path" {
  description = "GitLab project path allowed to assume the CI role."
  type        = string
  nullable    = false
}

variable "gitlab_branch" {
  description = "GitLab branch allowed to assume the CI role."
  type        = string
  default     = "main"
}

variable "oidc_thumbprint" {
  description = "Optional SHA-1 thumbprint of the GitLab OIDC issuer certificate."
  type        = string
  default     = null
}

variable "state_bucket_arn" {
  description = "ARN of the central OpenTofu state bucket."
  type        = string
  nullable    = false
}

variable "state_kms_key_arn" {
  description = "ARN of the KMS key protecting the central state bucket, if used."
  type        = string
  default     = ""
}
