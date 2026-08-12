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

variable "break_glass_role_arn" {
  description = "ARN of the break-glass role; exempted from user-creation and MFA denials. Empty disables the exception."
  type        = string
  default     = ""
}

variable "admin_ports" {
  description = "Ports that must never be opened to 0.0.0.0/0."
  type        = list(number)
  default     = [22, 3389, 1433, 3306]
}
