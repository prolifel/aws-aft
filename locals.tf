locals {
  name_prefix = var.name_prefix != "" ? var.name_prefix : "aws-hardened"

  cloudtrail_name = var.cloudtrail.bucket_name != "" ? var.cloudtrail.bucket_name : join("-", [
    local.name_prefix,
    "cloudtrail",
    data.aws_caller_identity.current.account_id,
    data.aws_region.current.region,
  ])
}
