mock_provider "aws" {
  mock_data "aws_ssoadmin_instances" {
    defaults = {
      arns               = ["arn:aws:sso:::instance/ssoins-test"]
      identity_store_ids = ["arn:aws:identitystore:::identitystore/test"]
    }
  }
}

run "management_plane" {
  command = apply

  variables {
    management_account = true
    name_prefix        = "test"
    ephp_ou_ids        = ["ou-test-1"]
    sso_group_arns = {
      "read-only" = ["arn:aws:identitystore:::group/test-group"]
    }
    allowed_log_account_ids = ["123456789012"]
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
    management_account  = false
    name_prefix         = "test"
    log_bucket_name     = "test-logs"
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
