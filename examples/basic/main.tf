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
  region = "us-east-1"
}

module "hardened" {
  source = "../../"

  name_prefix = "acme"
  tags        = { Environment = "production" }

  default_security_group_vpc_ids = []
}

output "cloudtrail_bucket_arn" {
  value = module.hardened.cloudtrail_bucket_arn
}
