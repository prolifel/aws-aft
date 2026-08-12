variable "enabled" {
  description = "Whether to create audit resources."
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

variable "region" {
  description = "AWS region."
  type        = string
}

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}

variable "log_bucket_name" {
  description = "Name of the shared log bucket. Empty auto-generates from prefix, account ID, and region."
  type        = string
  default     = ""
}

variable "log_bucket_arn" {
  description = "ARN of the shared log bucket (required on the account plane; created on the management plane)."
  type        = string
  default     = ""
}

variable "object_lock_retention_days" {
  description = "Object Lock COMPLIANCE retention period in days."
  type        = number
  default     = 2190
}

variable "allowed_log_account_ids" {
  description = "Account IDs allowed to deliver Config snapshots into the log bucket."
  type        = list(string)
  default     = []
}

variable "config_delegated_admin_account_id" {
  description = "Account ID to register as AWS Config delegated administrator."
  type        = string
  default     = ""
}

variable "config_rules" {
  description = "AWS Config managed rule identifiers to deploy on the account plane."
  type        = list(string)
  default = [
    "IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS",
    "IAM_USER_NO_POLICIES_CHECK",
    "ENCRYPTED_VOLUMES",
    "S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED",
    "RDS_STORAGE_ENCRYPTED",
    "IAM_USER_MFA_ENABLED",
    "ROOT_ACCOUNT_MFA_ENABLED",
    "VPC_DEFAULT_SECURITY_GROUP_CLOSED",
    "RESTRICTED_SSH",
    "RESTRICTED_COMMON_PORTS",
    "ALB_HTTP_TO_HTTPS_REDIRECTION_CHECK",
    "EC2_INSTANCE_MANAGED_BY_SSM",
  ]
}

variable "config_rule_parameters" {
  description = "Optional JSON input parameters per Config rule name."
  type        = map(string)
  default     = {}
}
