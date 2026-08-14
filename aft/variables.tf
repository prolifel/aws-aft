variable "ct_management_account_id" {
  description = "The AWS account ID of the Control Tower management account."
  type        = string
  nullable    = false
}

variable "log_archive_account_id" {
  description = "The AWS account ID of Log Archive"
  type        = string
  nullable    = false
}

variable "audit_account_id" {
  description = "The AWS account ID of Audit Account"
  type        = string
  nullable    = false
}

variable "aft_management_account_id" {
  description = "The AWS account ID of AFT Management Account"
  type        = string
  nullable    = false
}

variable "ct_home_region" {
  description = "The AWS region where Control Tower is deployed."
  type        = string
  nullable    = false
}
