terraform {
  required_version = ">= 1.8.0"
  backend "s3" {
    bucket = var.state_bucket_name
    key    = "01-management-init-role-and-hardening/terraform.tfstate"
    region = var.region
  }

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
