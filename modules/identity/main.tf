data "aws_caller_identity" "current" {}

locals {
  sso_enabled = var.enabled && var.management_account
  assignments = merge([
    for ps, groups in var.sso_group_arns : {
      for g in groups : "${ps}:${g}" => { permission_set = ps, group = g }
    }
  ]...)
  break_glass_policy = var.break_glass_policy != "" ? var.break_glass_policy : jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BreakGlassMinimal"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetBucketLocation",
          "cloudtrail:LookupEvents",
          "config:GetResourceConfigHistory",
          "ec2:DescribeInstances",
          "rds:DescribeDBInstances",
        ]
        Resource = "*"
      },
    ]
  })
}

data "aws_ssoadmin_instances" "this" {
  count = local.sso_enabled ? 1 : 0
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.sso_enabled ? var.sso_permission_sets : {}

  name             = each.key
  instance_arn     = data.aws_ssoadmin_instances.this[0].arns[0]
  session_duration = each.value.session_duration

  tags = var.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = {
    for k, v in var.sso_permission_sets : k => v
    if local.sso_enabled && v.managed_policy_arn != ""
  }

  instance_arn       = data.aws_ssoadmin_instances.this[0].arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  managed_policy_arn = each.value.managed_policy_arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each = {
    for k, v in var.sso_permission_sets : k => v
    if local.sso_enabled && v.inline_policy != ""
  }

  inline_policy      = each.value.inline_policy
  instance_arn       = data.aws_ssoadmin_instances.this[0].arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each = local.sso_enabled ? local.assignments : {}

  instance_arn       = data.aws_ssoadmin_instances.this[0].arns[0]
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_id       = each.value.group
  principal_type     = "GROUP"
  target_id          = var.sso_target_account_id != "" ? var.sso_target_account_id : data.aws_caller_identity.current.account_id
  target_type        = "AWS_ACCOUNT"
}

resource "aws_iam_account_password_policy" "strict" {
  count = var.enabled && !var.management_account && var.iam_password_policy.enabled ? 1 : 0

  minimum_password_length        = var.iam_password_policy.minimum_password_length
  require_lowercase_characters   = var.iam_password_policy.require_lowercase
  require_uppercase_characters   = var.iam_password_policy.require_uppercase
  require_numbers                = var.iam_password_policy.require_numbers
  require_symbols                = var.iam_password_policy.require_symbols
  allow_users_to_change_password = var.iam_password_policy.allow_users_to_change
  max_password_age               = var.iam_password_policy.max_password_age_days
  password_reuse_prevention      = var.iam_password_policy.password_reuse_prevention
}

resource "aws_iam_role" "break_glass" {
  count = var.enabled && !var.management_account ? 1 : 0

  name                 = var.break_glass_role_name
  assume_role_policy   = jsonencode({ Version = "2012-10-17", Statement = [] })
  max_session_duration = 3600

  inline_policy {
    name   = "break-glass-minimal"
    policy = local.break_glass_policy
  }

  tags = var.tags
}

resource "aws_sns_topic" "break_glass" {
  count = var.enabled && !var.management_account ? 1 : 0

  name = "${var.name_prefix}-break-glass-alerts"

  tags = var.tags
}

resource "aws_sns_topic_policy" "break_glass" {
  count = var.enabled && !var.management_account ? 1 : 0

  arn = aws_sns_topic.break_glass[0].arn
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowEventsToPublish"
        Effect    = "Allow"
        Principal = { Service = "events.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.break_glass[0].arn
      },
    ]
  })
}

resource "aws_cloudwatch_event_rule" "break_glass_assume" {
  count = var.enabled && !var.management_account ? 1 : 0

  name = "${var.name_prefix}-break-glass-assume"
  event_pattern = jsonencode({
    source      = ["aws.sts"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = ["sts.amazonaws.com"]
      eventName   = ["AssumeRole"]
      requestParameters = {
        roleArn = [aws_iam_role.break_glass[0].arn]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "break_glass_assume" {
  count = var.enabled && !var.management_account ? 1 : 0

  rule      = aws_cloudwatch_event_rule.break_glass_assume[0].name
  target_id = "break-glass-sns"
  arn       = aws_sns_topic.break_glass[0].arn
}
