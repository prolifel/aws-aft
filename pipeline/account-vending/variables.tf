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

variable "account_factory_product_id" {
  description = "Service Catalog product ID of Control Tower Account Factory."
  type        = string
  nullable    = false
}

variable "region" {
  description = "AWS region for the management-account provider."
  type        = string
  default     = "ap-southeast-3"
}
