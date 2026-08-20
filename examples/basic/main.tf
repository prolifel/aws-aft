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
  region = "ap-southeast-3"
}

module "hardened" {
  source = "../../modules/hardened"

  providers = {
    aws                 = aws
    aws.delegated_admin = aws
  }

  management_account = true
  name_prefix        = "acme"
  tags               = { Environment = "production" }

  ephp_ou_ids = ["ou-EXAMPLE"]

  sso_group_arns = {
    "read-only" = ["arn:aws:identitystore:::group/EXAMPLE-GROUP"]
  }

  kms_admin_arns = ["arn:aws:iam::123456789012:role/security-admin"]
}

output "scp_policy_ids" {
  value = module.hardened.scp_policy_ids
}
