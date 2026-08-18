variable "enabled" {
  description = "Whether to create identity resources."
  type        = bool
  default     = true
}

variable "management_account" {
  description = "Whether this module runs in the organization management account."
  type        = bool
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}

variable "sso_permission_sets" {
  description = "Map of SSO permission set name to configuration."
  type = map(object({
    managed_policy_arn = string
    inline_policy      = string
    session_duration   = string
  }))
  default = {
    "read-only" = {
      managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      inline_policy      = ""
      session_duration   = "PT8H"
    }
    "security-audit" = {
      managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
      inline_policy      = ""
      session_duration   = "PT4H"
    }
    "break-glass" = {
      managed_policy_arn = ""
      inline_policy      = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"NarrowBreakGlass\",\"Effect\":\"Allow\",\"Action\":[\"sts:GetCallerIdentity\",\"cloudtrail:LookupEvents\",\"s3:GetObject\"],\"Resource\":\"*\"}]}"
      session_duration   = "PT1H"
    }
  }
}

variable "sso_group_arns" {
  description = "Map of permission set name to list of Identity Center group ARNs (or group IDs) to assign."
  type        = map(list(string))
  default     = {}
}

variable "sso_target_account_id" {
  description = "Account ID to assign permission sets to. Defaults to the calling account."
  type        = string
  default     = ""
}

variable "iam_password_policy" {
  description = "IAM account password policy settings."
  type = object({
    enabled                   = bool
    minimum_password_length   = number
    require_lowercase         = bool
    require_uppercase         = bool
    require_numbers           = bool
    require_symbols           = bool
    allow_users_to_change     = bool
    max_password_age_days     = number
    password_reuse_prevention = number
  })
  default = {
    enabled                   = true
    minimum_password_length   = 14
    require_lowercase         = true
    require_uppercase         = true
    require_numbers           = true
    require_symbols           = true
    allow_users_to_change     = true
    max_password_age_days     = 90
    password_reuse_prevention = 24
  }
}

variable "break_glass_role_name" {
  description = "Name of the break-glass role."
  type        = string
  default     = "break-glass"
}

variable "break_glass_policy" {
  description = "Inline policy JSON for the break-glass role."
  type        = string
  default     = ""
}

variable "break_glass_user_name" {
  description = "Name of the management-account IAM user allowed to assume the break-glass role."
  type        = string
  default     = "break-glass-user"
}

variable "break_glass_mgmt_role_arn" {
  description = "ARN of the management-account break-glass role; used as the child-account role trust principal. Empty keeps the child-account role untrusted."
  type        = string
  default     = ""
}

variable "break_glass_target_account_ids" {
  description = "Child account IDs whose break-glass roles the management-account break-glass role may assume. Empty on the child plane."
  type        = list(string)
  default     = []
}
