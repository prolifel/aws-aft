terraform {
  required_version = ">= 1.8.0"

  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "6.58.0"
      configuration_aliases = [aws, aws.delegated_admin]
    }
  }
}
