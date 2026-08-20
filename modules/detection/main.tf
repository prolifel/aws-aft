data "aws_caller_identity" "current" {}

locals {
  guardduty_admin = var.guardduty_admin_account_id != "" ? var.guardduty_admin_account_id : data.aws_caller_identity.current.account_id
  inspector_admin = var.inspector_admin_account_id != "" ? var.inspector_admin_account_id : data.aws_caller_identity.current.account_id
  macie_admin     = var.macie_admin_account_id != "" ? var.macie_admin_account_id : data.aws_caller_identity.current.account_id
}

resource "aws_guardduty_detector" "org" {
  count = var.enabled && var.management_account ? 1 : 0

  provider                     = aws.guardduty
  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_guardduty_organization_admin_account" "this" {
  count = var.enabled && var.management_account ? 1 : 0

  admin_account_id = local.guardduty_admin
}

resource "aws_guardduty_organization_configuration" "this" {
  count = var.enabled && var.management_account ? 1 : 0

  provider                         = aws.guardduty
  detector_id                      = aws_guardduty_detector.org[0].id
  auto_enable_organization_members = "ALL"

  depends_on = [
    aws_guardduty_detector.org,
    aws_guardduty_organization_admin_account.this,
  ]
}

resource "aws_securityhub_account" "org" {
  count = var.enabled && var.management_account ? 1 : 0
}

resource "aws_securityhub_organization_configuration" "this" {
  count = var.enabled && var.management_account ? 1 : 0

  auto_enable = true

  depends_on = [aws_securityhub_account.org]
}

resource "aws_inspector2_delegated_admin_account" "this" {
  count = var.enabled && var.management_account ? 1 : 0

  account_id = local.inspector_admin
}

resource "aws_inspector2_enabler" "this" {
  count = var.enabled && var.management_account ? 1 : 0

  account_ids    = [local.inspector_admin]
  resource_types = ["EC2", "LAMBDA", "ECR"]

  depends_on = [aws_inspector2_delegated_admin_account.this]
}

resource "aws_macie2_account" "org" {
  count = var.enabled && var.management_account ? 1 : 0
}

resource "aws_macie2_organization_admin_account" "this" {
  count = var.enabled && var.management_account ? 1 : 0

  admin_account_id = local.macie_admin
}

resource "aws_guardduty_detector" "this" {
  count = var.enabled && !var.management_account ? 1 : 0

  enable                       = true
  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

resource "aws_iam_role" "malware_protection" {
  count = var.enabled && !var.management_account && length(var.malware_protection_s3_bucket_arns) > 0 ? 1 : 0

  name = "${var.name_prefix}-guardduty-malware"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "malware-protection.guardduty.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "malware_protection" {
  count = var.enabled && !var.management_account && length(var.malware_protection_s3_bucket_arns) > 0 ? 1 : 0

  role       = aws_iam_role.malware_protection[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonGuardDutyMalwareProtectionServiceRolePolicy"
}

resource "aws_guardduty_malware_protection_plan" "s3" {
  for_each = var.enabled && !var.management_account ? toset(var.malware_protection_s3_bucket_arns) : toset([])

  role = aws_iam_role.malware_protection[0].arn

  protected_resource {
    s3_bucket {
      bucket_name = each.value
    }
  }

  tags = var.tags
}

resource "aws_macie2_account" "this" {
  count = var.enabled && !var.management_account ? 1 : 0
}

resource "aws_macie2_classification_job" "this" {
  count = var.enabled && !var.management_account && length(var.macie_s3_bucket_arns) > 0 ? 1 : 0

  name     = "${var.name_prefix}-sensitive-data-scan"
  job_type = "ONE_TIME"

  s3_job_definition {
    bucket_definitions {
      account_id = data.aws_caller_identity.current.account_id
      buckets    = var.macie_s3_bucket_arns
    }
  }

  depends_on = [aws_macie2_account.this]
}

resource "aws_securityhub_account" "this" {
  count = var.enabled && !var.management_account ? 1 : 0
}

resource "aws_securityhub_standards_subscription" "this" {
  for_each = var.enabled && !var.management_account ? var.securityhub_standards : {}

  standards_arn = each.value

  depends_on = [aws_securityhub_account.this]
}
