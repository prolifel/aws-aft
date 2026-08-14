terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket  = "aws-hardened-state-<MANAGEMENT_ACCOUNT_ID>-<REGION>" # paste from 00-backend output
    key     = "management-init-role-and-hardening/terraform.tfstate"
    region  = "ap-southeast-3"
    encrypt = true
  }

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.58.0"
    }
  }
}
