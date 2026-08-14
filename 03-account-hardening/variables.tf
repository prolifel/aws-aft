variable "config_bucket_name" {
  description = "Name of the handoff config bucket (set by the pipeline from CONFIG_BUCKET_ARN)."
  type        = string
  nullable    = false
}

variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "prod"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-3"
}

variable "tags" {
  description = "Tags applied to resources."
  type        = map(string)
  default     = {}
}
