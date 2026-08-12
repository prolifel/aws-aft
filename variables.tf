variable "name_prefix" {
  description = "Prefix for generated resource names. Leave empty to use a default."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

variable "s3_account_public_access_block" {
  description = "Account-level S3 public access block settings."
  type = object({
    enabled                 = bool
    block_public_acls       = bool
    block_public_policy     = bool
    ignore_public_acls      = bool
    restrict_public_buckets = bool
  })
  default = {
    enabled                 = true
    block_public_acls       = true
    block_public_policy     = true
    ignore_public_acls      = true
    restrict_public_buckets = true
  }
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

variable "ebs_encryption" {
  description = "EBS default encryption settings."
  type = object({
    enabled = bool
  })
  default = {
    enabled = true
  }
}

variable "guardduty" {
  description = "GuardDuty detector settings."
  type = object({
    enabled                      = bool
    finding_publishing_frequency = string
  })
  default = {
    enabled                      = true
    finding_publishing_frequency = "FIFTEEN_MINUTES"
  }
}

variable "cloudtrail" {
  description = "CloudTrail trail and log bucket settings."
  type = object({
    enabled                       = bool
    multi_region                  = bool
    bucket_name                   = string
    retention_days                = number
    force_destroy                 = bool
    include_global_service_events = bool
  })
  default = {
    enabled                       = true
    multi_region                  = true
    bucket_name                   = ""
    retention_days                = 90
    force_destroy                 = false
    include_global_service_events = true
  }
}

variable "default_security_group_vpc_ids" {
  description = "VPC IDs whose default security groups should have all ingress/egress rules removed."
  type        = list(string)
  default     = []
}
