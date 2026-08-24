variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-3"
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "prod"
}

variable "tags" {
  description = "Tags applied to resources."
  type        = map(string)
  default     = {}
}

variable "gitlab_url" {
  description = "GitLab OIDC issuer base URL, e.g. https://gitlab.example.com."
  type        = string
  nullable    = false
}

variable "gitlab_branch" {
  description = "Branch allowed to assume the GitLab CI role."
  type        = string
  nullable    = false
}

variable "gitlab_project_path" {
  description = "GitLab project path, e.g. prolifel/aws-aft."
  type        = string
  nullable    = false
}

variable "ephp_ou_ids" {
  description = "OU IDs to attach the SCPs to."
  type        = list(string)
  nullable    = false
}

variable "break_glass_user_name" {
  description = "Name of the management-account IAM user allowed to assume the break-glass role."
  type        = string
  default     = "break-glass-user"
}

variable "sso_target_account_id" {
  description = "Account ID to assign permission sets to. Empty uses the calling account."
  type        = string
  default     = ""
}

variable "guardduty_admin_account_id" {
  description = "GuardDuty delegated admin account ID."
  type        = string
  default     = ""
}

variable "securityhub_admin_account_id" {
  description = "Security Hub delegated admin account ID."
  type        = string
  default     = ""
}

variable "inspector_admin_account_id" {
  description = "Inspector2 delegated admin account ID."
  type        = string
  default     = ""
}

variable "macie_admin_account_id" {
  description = "Macie delegated admin account ID."
  type        = string
  default     = ""
}

variable "organization_id" {
  description = "ID of AWS Organization"
  type        = string
  nullable    = false
}

variable "oidc_thumbprint" {
  description = "oidc thumbprint"
  type        = string
  nullable    = false
}
