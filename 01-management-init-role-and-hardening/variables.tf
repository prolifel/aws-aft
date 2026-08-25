variable "region" {
  description = "AWS region for management-plane resources."
  type        = string
  default     = "ap-southeast-3"
}

variable "name_prefix" {
  description = "Prefix for management-plane resource names."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Tags applied to management-plane resources."
  type        = map(string)
  default     = {}
}

variable "gitlab_url" {
  description = "GitLab OIDC issuer base URL."
  type        = string
  nullable    = false
}

variable "gitlab_branch" {
  description = "GitLab branch allowed to assume the CI role."
  type        = string
  default     = "main"
}

variable "gitlab_project_path" {
  description = "GitLab project path allowed to assume the CI role."
  type        = string
  nullable    = false
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
  description = "ARN of the optional state KMS key."
  type        = string
  default     = ""
}
