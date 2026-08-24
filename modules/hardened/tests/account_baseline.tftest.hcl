mock_provider "aws" {
  override_resource {
    target = module.identity.aws_ssoadmin_permission_set.this
    values = {
      arn = "arn:aws:sso:::permissionSet/ssoins-test/ps-000000000000"
    }
  }

  override_resource {
    target = module.encryption.aws_kms_key.this
    values = {
      arn = "arn:aws:kms:ap-southeast-3:123456789012:key/00000000-0000-4000-8000-000000000001"
    }
  }

  override_resource {
    target = module.identity.aws_sns_topic.break_glass
    values = {
      arn = "arn:aws:sns:ap-southeast-3:123456789012:test-break-glass-alerts"
    }
  }

  override_resource {
    target = module.ci.aws_iam_role.gitlab_ci
    values = {
      arn = "arn:aws:iam::123456789012:role/test-gitlab-ci"
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

  mock_data "aws_organizations_organization" {
    defaults = {
      accounts = [
        {
          id               = "123456789012"
          arn              = "arn:aws:organizations::123456789012:account/o-test/123456789012"
          email            = "mgmt@example.com"
          name             = "management"
          joined_method    = "INVITED"
          joined_timestamp = "2026-01-01T00:00:00Z"
          state            = "ACTIVE"
          status           = "ACTIVE"
        },
        {
          id               = "210987654321"
          arn              = "arn:aws:organizations::123456789012:account/o-test/210987654321"
          email            = "child@example.com"
          name             = "child"
          joined_method    = "INVITED"
          joined_timestamp = "2026-01-01T00:00:00Z"
          state            = "ACTIVE"
          status           = "ACTIVE"
        },
      ]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
      arn        = "arn:aws:iam::123456789012:root"
      user_id    = "test"
    }
  }
}

mock_provider "aws" {
  alias = "delegated_admin"
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
    guardduty_admin_account_id = "123456789012"
    inspector_admin_account_id = "123456789012"
    macie_admin_account_id     = "123456789012"
  }

  assert {
    condition     = output.scp_policy_id != "" && output.scp_policy_name == "test-hardening"
    error_message = "management plane must create exactly one SCP"
  }
  assert {
    condition     = length(output.sso_permission_set_names) == 3
    error_message = "management plane must create the 3 default SSO permission sets"
  }
  assert {
    condition     = output.break_glass_role_arn != ""
    error_message = "management plane must create the break-glass role"
  }
  assert {
    condition     = output.break_glass_user_name == "break-glass-user"
    error_message = "management plane must create the break-glass IAM user"
  }
  assert {
    condition     = can(regex("user/break-glass-user", module.identity.break_glass_role_trust_policy))
    error_message = "mgmt break-glass role must trust the designated IAM user"
  }
  assert {
    condition     = can(regex("arn:aws:iam::210987654321:role/break-glass", module.identity.break_glass_mgmt_role_policy))
    error_message = "mgmt break-glass role must be able to assume child break-glass roles"
  }
}

run "account_plane" {
  command = apply

  variables {
    management_account        = false
    name_prefix               = "test"
    break_glass_mgmt_role_arn = "arn:aws:iam::123456789012:role/break-glass"
  }

  assert {
    condition     = output.scp_policy_id == ""
    error_message = "account plane must not create SCPs"
  }
  assert {
    condition     = output.break_glass_role_name != ""
    error_message = "account plane must create the break-glass role"
  }
  assert {
    condition     = output.kms_key_id != ""
    error_message = "account plane must create the KMS CMK"
  }
  assert {
    condition     = output.guardduty_detector_id != ""
    error_message = "account plane must create the GuardDuty detector"
  }
  assert {
    condition     = output.gitlab_ci_role_arn == ""
    error_message = "ci module must be a no-op on the account plane"
  }
  assert {
    condition     = can(regex("arn:aws:iam::123456789012:role/break-glass", module.identity.break_glass_role_trust_policy))
    error_message = "child break-glass role must trust the management break-glass role"
  }
  assert {
    condition     = can(regex("iam:CreateUser", module.identity.break_glass_role_policy))
    error_message = "child break-glass role must be able to create IAM users"
  }
  assert {
    condition     = !can(regex("iam:CreateAccessKey", module.identity.break_glass_role_policy))
    error_message = "child break-glass role must not create access keys"
  }
}

run "ci_management_plane" {
  command = apply

  variables {
    management_account    = true
    name_prefix           = "test"
    ci_enabled            = true
    gitlab_url            = "https://gitlab.example.com"
    gitlab_project_path   = "prolifel/aws-aft"
    config_bucket_arn     = "arn:aws:s3:::test-config"
    ephp_ou_ids           = ["ou-test-1"]
    sso_target_account_id = "123456789012"
    sso_group_arns = {
      "read-only" = ["arn:aws:identitystore:::group/00000000-0000-4000-8000-000000000000"]
    }
    guardduty_admin_account_id = "123456789012"
    inspector_admin_account_id = "123456789012"
    macie_admin_account_id     = "123456789012"
  }

  assert {
    condition     = output.gitlab_ci_role_arn == "arn:aws:iam::123456789012:role/test-gitlab-ci"
    error_message = "ci_enabled must create the GitLab CI role on the management plane"
  }
}
