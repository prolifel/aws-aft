terraform {
  required_version = ">= 1.8.0"

  backend "s3" {
    bucket  = "aws-hardened-state-373901294232-us-west-2"
    key     = "placeholder" # per-account key passed at tofu init
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
