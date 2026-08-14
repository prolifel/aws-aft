module "aft" {
  source = "github.com/aws-ia/terraform-aws-control_tower_account_factory"

  # required vars
  ct_management_account_id  = var.ct_management_account_id
  log_archive_account_id    = var.log_archive_account_id
  audit_account_id          = var.audit_account_id
  aft_management_account_id = var.aft_management_account_id
  ct_home_region            = var.ct_home_region

  # vcs provider
  vcs_provider                                  = "github"
  account_request_repo_name                     = "prolifel/aws-aft"
  account_customizations_repo_name              = "prolifel/aws-aft"
  account_provisioning_customizations_repo_name = "prolifel/aws-aft"
  global_customizations_repo_name               = "prolifel/aws-aft"

  # additional vars
  aft_feature_delete_default_vpcs_enabled    = true
  aft_feature_enterprise_support             = false
  aft_enable_vpc                             = false
  aft_metrics_reporting                      = false
  aft_vpc_endpoints                          = false
  cloudwatch_log_group_enable_cmk_encryption = false
  sns_topic_enable_cmk_encryption            = false
}
