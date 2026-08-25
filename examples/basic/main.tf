terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.58.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for the account baseline."
  type        = string
  default     = "ap-southeast-3"
}

variable "security_contact_email" {
  description = "Security alternate-contact email."
  type        = string
  default     = "security@example.invalid"
}

variable "billing_contact_email" {
  description = "Billing alternate-contact email."
  type        = string
  default     = "billing@example.invalid"
}

variable "operations_contact_email" {
  description = "Operations alternate-contact email."
  type        = string
  default     = "operations@example.invalid"
}

variable "jarjit_trust_account_id" {
  description = "Placeholder account ID trusted by the baseline role."
  type        = string
  default     = "000000000000"
}

variable "jarjit_org_id" {
  description = "Placeholder AWS Organizations ID for the baseline role."
  type        = string
  default     = "o-example"
}

variable "break_glass_user_arn" {
  description = "Placeholder break-glass user ARN."
  type        = string
  default     = "arn:aws:iam::000000000000:user/example-break-glass"
}

variable "bmc_discovery_user_arn" {
  description = "Placeholder BMC discovery user ARN."
  type        = string
  default     = "arn:aws:iam::000000000000:user/example-bmc-discovery"
}

variable "bmc_kms_account_id" {
  description = "Placeholder account ID for BMC KMS access."
  type        = string
  default     = "000000000000"
}

variable "terraform_central_role_arn" {
  description = "Placeholder central Terraform role ARN."
  type        = string
  default     = "arn:aws:iam::000000000000:role/example-terraform-central"
}

module "account_bootstrap" {
  source = "../../modules/account-bootstrap"

  security_contact_name      = "Example Security Team"
  security_contact_email     = var.security_contact_email
  security_contact_phone     = "+6200000000000"
  billing_contact_name       = "Example FinOps Team"
  billing_contact_email      = var.billing_contact_email
  billing_contact_phone      = "+6200000000000"
  operations_contact_name    = "Example Platform Team"
  operations_contact_email   = var.operations_contact_email
  operations_contact_phone   = "+6200000000000"
  jarjit_trust_account_id    = var.jarjit_trust_account_id
  jarjit_org_id              = var.jarjit_org_id
  break_glass_user_arn       = var.break_glass_user_arn
  bmc_discovery_user_arn     = var.bmc_discovery_user_arn
  bmc_kms_account_id         = var.bmc_kms_account_id
  terraform_central_role_arn = var.terraform_central_role_arn
}
