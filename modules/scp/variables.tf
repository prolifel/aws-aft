variable "enabled" {
  description = "Whether to create SCPs."
  type        = bool
  default     = true
}

variable "management_account" {
  description = "Whether this module runs in the organization management account."
  type        = bool
}

variable "name_prefix" {
  description = "Prefix for SCP names."
  type        = string
}

variable "ephp_ou_ids" {
  description = "OU IDs to attach the SCPs to."
  type        = list(string)
  default     = []
}

variable "break_glass_exempt_arns" {
  description = "ARNs of break-glass roles exempted from user-creation, inline-policy, and MFA SCP denials. Empty disables the exception."
  type        = list(string)
  default     = []
}
