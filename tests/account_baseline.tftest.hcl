mock_provider "aws" {
  override_resource {
    target = module.identity.aws_ssoadmin_permission_set.this["read-only"]
    values = {
      arn = "arn:aws:sso:::permissionSet/ssoins-test/ps-000000000000"
    }
  }

  override_resource {
    target = module.identity.aws_ssoadmin_permission_set.this["security-audit"]
    values = {
      arn = "arn:aws:sso:::permissionSet/ssoins-test/ps-000000000001"
    }
  }

  override_resource {
    target = module.identity.aws_ssoadmin_permission_set.this["break-glass"]
    values = {
      arn = "arn:aws:sso:::permissionSet/ssoins-test/ps-000000000002"
    }
  }

  override_resource {
    target = module.audit.aws_kms_key.logs[0]
    values = {
      arn = "arn:aws:kms:ap-southeast-3:123456789012:key/00000000-0000-4000-8000-000000000000"
    }
  }

  override_resource {
    target = module.encryption.aws_kms_key.this[0]
    values = {
      arn = "arn:aws:kms:ap-southeast-3:123456789012:key/00000000-0000-4000-8000-000000000001"
    }
  }

  override_resource {
    target = module.identity.aws_sns_topic.break_glass[0]
    values = {
      arn = "arn:aws:sns:ap-southeast-3:123456789012:test-break-glass-alerts"
    }
  }

  override_resource {
    target = module.audit.aws_iam_role.config[0]
    values = {
      arn = "arn:aws:iam::123456789012:role/test-config"
    }
  }

  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-test"]
      identity_store_ids = ["arn:aws:identitystore:::identitystore/test"]
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

run "management_plane" {
  command = apply

  variables {
    management_account    = true
    name_prefix           = "test"
    ephp_ou_ids           = ["ou-test-1"]
    sso_target_account_id = "123456789012"
    sso_group_arns = {
      "read-only" = ["arn:aws:identitystore:::group/00000000-0000-4000-8000-000000000000"]
    }
    allowed_log_account_ids    = ["123456789012"]
    guardduty_admin_account_id = "123456789012"
    inspector_admin_account_id = "123456789012"
    macie_admin_account_id     = "123456789012"
  }

  assert {
    condition     = length(output.scp_policy_ids) == 5
    error_message = "management plane must create exactly 5 SCPs"
  }
  assert {
    condition     = length(output.sso_permission_set_names) == 3
    error_message = "management plane must create the 3 default SSO permission sets"
  }
  assert {
    condition     = output.cloudtrail_id != ""
    error_message = "management plane must create the org CloudTrail"
  }
  assert {
    condition     = output.log_bucket_id != ""
    error_message = "management plane must create the log bucket"
  }
}

run "account_plane" {
  command = apply

  variables {
    management_account      = false
    name_prefix             = "test"
    log_bucket_name         = "test-logs"
    allowed_log_account_ids = ["123456789012"]
  }

  assert {
    condition     = length(output.scp_policy_ids) == 0
    error_message = "account plane must not create SCPs"
  }
  assert {
    condition     = output.break_glass_role_name != ""
    error_message = "account plane must create the break-glass role"
  }
  assert {
    condition     = output.config_recorder_id != ""
    error_message = "account plane must create the Config recorder"
  }
  assert {
    condition     = output.kms_key_id != ""
    error_message = "account plane must create the KMS CMK"
  }
  assert {
    condition     = output.guardduty_detector_id != ""
    error_message = "account plane must create the GuardDuty detector"
  }
}
