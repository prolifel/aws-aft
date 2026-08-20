data "aws_s3_object" "config" {
  bucket = var.config_bucket_name
  key    = "config.json"
}

locals {
  config = jsondecode(data.aws_s3_object.config.body)
}

module "hardened" {
  source = "../../modules/hardened"

  providers = {
    aws                 = aws
    aws.delegated_admin = aws
  }

  management_account        = false
  name_prefix               = var.name_prefix
  region                    = var.region
  tags                      = var.tags
  log_bucket_name           = local.config.log_bucket_name
  log_bucket_arn            = local.config.log_bucket_arn
  break_glass_mgmt_role_arn = local.config.break_glass_mgmt_role_arn
}
