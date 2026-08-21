variable "name_prefix" {
  description = "Prefix for resource names."
  type        = string
  default     = "aws-hardened"
}

variable "region" {
  description = "AWS region."
  type        = string
  default     = "ap-southeast-3"
}

variable "tags" {
  description = "Tags applied to all resources created by this module."
  type        = map(string)
  default     = {}
}

variable "management_account" {
  description = "Whether this module runs in the organization management account."
  type        = bool
}

variable "ci_enabled" {
  description = "Whether to create GitLab CI OIDC resources (management account only)."
  type        = bool
  default     = false
}

variable "gitlab_url" {
  description = "GitLab OIDC issuer base URL, e.g. https://gitlab.example.com."
  type        = string
  default     = ""
}

variable "gitlab_project_path" {
  description = "GitLab project path for the CI trust condition, e.g. prolifel/aws-aft."
  type        = string
  default     = ""
}

variable "gitlab_branch" {
  description = "Branch allowed to assume the GitLab CI role."
  type        = string
  default     = "main"
}

variable "oidc_thumbprint" {
  description = "Optional SHA-1 thumbprint of the GitLab OIDC issuer cert."
  type        = string
  default     = null
}

variable "config_bucket_arn" {
  description = "ARN of the handoff config bucket used by account-plane jobs."
  type        = string
  default     = ""
}

variable "encryption_enabled" {
  description = "Whether to create encryption resources."
  type        = bool
  default     = true
}

variable "identity_enabled" {
  description = "Whether to create identity resources."
  type        = bool
  default     = true
}

variable "scp_enabled" {
  description = "Whether to create SCPs (management account only)."
  type        = bool
  default     = true
}

variable "audit_enabled" {
  description = "Whether to create audit resources."
  type        = bool
  default     = true
}

variable "detection_enabled" {
  description = "Whether to create detection resources."
  type        = bool
  default     = true
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

variable "break_glass_role_name" {
  description = "Name of the break-glass role."
  type        = string
  default     = "break-glass"
}

variable "break_glass_user_name" {
  description = "Name of the management-account IAM user allowed to assume the break-glass role."
  type        = string
  default     = "break-glass-user"
}

variable "break_glass_mgmt_role_arn" {
  description = "ARN of the management-account break-glass role. Child-plane callers must set this so per-account roles trust it. Empty on the management plane derives it from the org."
  type        = string
  default     = ""
}

variable "sso_permission_sets" {
  description = "Map of SSO permission set name to configuration."
  type = map(object({
    managed_policy_arn = string
    inline_policy      = string
    session_duration   = string
  }))
  default = {
    "read-only" = {
      managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
      inline_policy      = ""
      session_duration   = "PT8H"
    }
    "security-audit" = {
      managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
      inline_policy      = ""
      session_duration   = "PT4H"
    }
    "break-glass" = {
      managed_policy_arn = ""
      inline_policy      = "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Sid\":\"NarrowBreakGlass\",\"Effect\":\"Allow\",\"Action\":[\"sts:GetCallerIdentity\",\"cloudtrail:LookupEvents\",\"s3:GetObject\"],\"Resource\":\"*\"}]}"
      session_duration   = "PT1H"
    }
  }
}

variable "sso_group_arns" {
  description = "Map of permission set name to list of Identity Center group ARNs (or group IDs) to assign."
  type        = map(list(string))
  default     = {}
}

variable "sso_target_account_id" {
  description = "Account ID to assign permission sets to. Defaults to the calling account."
  type        = string
  default     = ""
}

variable "ephp_ou_ids" {
  description = "OU IDs to attach the SCPs to."
  type        = list(string)
  default     = []
}

variable "log_bucket_name" {
  description = "Name of the shared log bucket. Empty auto-generates on the management account."
  type        = string
  default     = ""
}

variable "log_bucket_arn" {
  description = "ARN of the shared log bucket (required on the account plane)."
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

# note: aws config enabled via control tower

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
    "RESTRICTED_INCOMING_TRAFFIC",
  ]
}

variable "config_rule_parameters" {
  description = "Optional JSON input parameters per Config rule name."
  type        = map(string)
  default     = {}
}

variable "remediation_rules" {
  description = "AWS Config auto-remediation per managed rule: SSM document, automatic flag, static and resource parameters."
  type = map(object({
    ssm_document        = string
    automatic           = optional(bool, true)
    static_parameters   = optional(map(string), {})
    resource_parameters = optional(map(string), {})
  }))
  default = {
    ENCRYPTED_VOLUMES = {
      ssm_document = "AWSConfigRemediation-EnableEbsEncryptionByDefault"
    }
    S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED = {
      ssm_document        = "AWS-EnableS3BucketEncryption"
      resource_parameters = { BucketName = "RESOURCE_ID" }
      static_parameters   = { SSEAlgorithm = "AES256" }
    }
  }
}

variable "guardduty_admin_account_id" {
  description = "GuardDuty delegated admin account ID. Empty uses the calling account."
  type        = string
  default     = ""
}

variable "securityhub_admin_account_id" {
  description = "Security Hub delegated admin account ID. Empty uses the calling account."
  type        = string
  default     = ""
}

variable "inspector_admin_account_id" {
  description = "Inspector2 delegated admin account ID. Empty uses the calling account."
  type        = string
  default     = ""
}

variable "macie_admin_account_id" {
  description = "Macie delegated admin account ID. Empty uses the calling account."
  type        = string
  default     = ""
}

variable "securityhub_standards" {
  description = "Map of SecurityHub standard name to standards ARN."
  type        = map(string)
  default = {
    "aws-foundational-security-best-practices" = "arn:aws:securityhub:::ruleset/aws-foundational-security-best-practices/v/1.0.0"
    "cis-aws-foundations-benchmark"            = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.4.1"
    "hipaa"                                    = "arn:aws:securityhub:::ruleset/hipaa/v/1.0.0"
  }
}

variable "malware_protection_s3_bucket_arns" {
  description = "S3 bucket ARNs to enable GuardDuty malware protection for."
  type        = list(string)
  default     = []
}

variable "macie_s3_bucket_arns" {
  description = "S3 bucket ARNs to classify with the Macie job."
  type        = list(string)
  default     = []
}
