terraform {
  required_version = ">= 1.8.0"

  # Empty configurable s3 backend: CI passes -backend-config=bucket=... key=...
  # region=... at init time. No bucket name is hardcoded here.
  backend "s3" {}

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
