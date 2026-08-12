variable "enabled" {
  description = "Whether to create detection resources."
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

variable "tags" {
  description = "Tags applied to created resources."
  type        = map(string)
  default     = {}
}

variable "guardduty_admin_account_id" {
  description = "GuardDuty delegated admin account ID. Empty uses the calling account."
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
  description = "S3 bucket ARNs to enable GuardDuty malware protection for (account plane)."
  type        = list(string)
  default     = []
}

variable "macie_s3_bucket_arns" {
  description = "S3 bucket ARNs to classify with the Macie job (account plane)."
  type        = list(string)
  default     = []
}
