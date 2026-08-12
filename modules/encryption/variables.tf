variable "enabled" {
  description = "Whether to create encryption resources."
  type        = bool
  default     = true
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

variable "kms_admin_arns" {
  description = "IAM principal ARNs allowed to administer the CMK."
  type        = list(string)
  default     = []
}

variable "kms_user_arns" {
  description = "IAM principal ARNs allowed to use the CMK."
  type        = list(string)
  default     = []
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

variable "ebs_encryption_enabled" {
  description = "Whether to enable EBS default encryption."
  type        = bool
  default     = true
}
