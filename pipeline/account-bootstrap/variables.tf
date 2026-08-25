variable "security_contact_name" {
  description = "Name of the security alternate contact."
  type        = string
  nullable    = false
}
variable "security_contact_email" {
  description = "Email of the security alternate contact."
  type        = string
  nullable    = false
}
variable "security_contact_phone" {
  description = "Phone of the security alternate contact."
  type        = string
  nullable    = false
}
variable "security_contact_title" {
  description = "Title of the security alternate contact."
  type        = string
  default     = "Cloud Security Team"
}
variable "billing_contact_name" {
  description = "Name of the billing alternate contact."
  type        = string
  nullable    = false
}
variable "billing_contact_email" {
  description = "Email of the billing alternate contact."
  type        = string
  nullable    = false
}
variable "billing_contact_phone" {
  description = "Phone of the billing alternate contact."
  type        = string
  nullable    = false
}
variable "billing_contact_title" {
  description = "Title of the billing alternate contact."
  type        = string
  default     = "Cloud FinOps Team"
}
variable "operations_contact_name" {
  description = "Name of the operations alternate contact."
  type        = string
  nullable    = false
}
variable "operations_contact_email" {
  description = "Email of the operations alternate contact."
  type        = string
  nullable    = false
}
variable "operations_contact_phone" {
  description = "Phone of the operations alternate contact."
  type        = string
  nullable    = false
}
variable "operations_contact_title" {
  description = "Title of the operations alternate contact."
  type        = string
  default     = "Cloud Platform Engineering Team"
}
variable "region" {
  description = "AWS region for the single-region baseline provider."
  type        = string
  default     = "ap-southeast-3"
}
