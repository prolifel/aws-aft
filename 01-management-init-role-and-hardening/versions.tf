terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket  = "aws-hardened-state-373901294232-us-west-2" # paste from 00-backend output
    key     = "management-init-role-and-hardening/terraform.tfstate"
    region  = "us-west-2"
    encrypt = true
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
