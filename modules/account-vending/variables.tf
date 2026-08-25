variable "account_name" {
  description = "Desired AWS account name (identity; immutable after creation)."
  type        = string
  nullable    = false
}

variable "email" {
  description = "Desired AWS account root email (identity; immutable after creation)."
  type        = string
  nullable    = false
}

variable "managed_org_unit" {
  description = "Target OU name (identity; explicit operation required to move)."
  type        = string
  nullable    = false
}

variable "account_tags" {
  description = "Tags applied to the account and metadata."
  type        = map(string)
  default     = {}
}

variable "product_name" {
  description = "Control Tower Account Factory Service Catalog product name."
  type        = string
  default     = "AWS Control Tower Account Factory"
}

variable "sso_user_email" {
  description = "Email of the SSO user to assign to the vended account. Empty string omits the SSO parameter."
  type        = string
  default     = ""
  nullable    = true
}

variable "sso_user_first_name" {
  description = "First name of the SSO user to assign to the vended account. Empty string omits the SSO parameter."
  type        = string
  default     = ""
  nullable    = true
}

variable "sso_user_last_name" {
  description = "Last name of the SSO user to assign to the vended account. Empty string omits the SSO parameter."
  type        = string
  default     = ""
  nullable    = true
}

variable "account_factory_product_id" {
  description = "Service Catalog product ID of Control Tower Account Factory."
  type        = string
  nullable    = false
}
