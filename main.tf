resource "aws_s3_account_public_access_block" "this" {
  count = var.s3_account_public_access_block.enabled ? 1 : 0

  block_public_acls       = var.s3_account_public_access_block.block_public_acls
  block_public_policy     = var.s3_account_public_access_block.block_public_policy
  ignore_public_acls      = var.s3_account_public_access_block.ignore_public_acls
  restrict_public_buckets = var.s3_account_public_access_block.restrict_public_buckets
}

resource "aws_iam_account_password_policy" "strict" {
  count = var.iam_password_policy.enabled ? 1 : 0

  minimum_password_length        = var.iam_password_policy.minimum_password_length
  require_lowercase_characters   = var.iam_password_policy.require_lowercase
  require_uppercase_characters   = var.iam_password_policy.require_uppercase
  require_numbers                = var.iam_password_policy.require_numbers
  require_symbols                = var.iam_password_policy.require_symbols
  allow_users_to_change_password = var.iam_password_policy.allow_users_to_change
  max_password_age               = var.iam_password_policy.max_password_age_days
  password_reuse_prevention      = var.iam_password_policy.password_reuse_prevention
}

resource "aws_ebs_encryption_by_default" "this" {
  count = var.ebs_encryption.enabled ? 1 : 0

  enabled = true
}

resource "aws_guardduty_detector" "this" {
  count = var.guardduty.enabled ? 1 : 0

  enable                       = true
  finding_publishing_frequency = var.guardduty.finding_publishing_frequency
}

resource "aws_cloudtrail" "this" {
  count = var.cloudtrail.enabled ? 1 : 0

  name                          = local.cloudtrail_name
  s3_bucket_name                = aws_s3_bucket.cloudtrail[0].id
  include_global_service_events = var.cloudtrail.include_global_service_events
  is_multi_region_trail         = var.cloudtrail.multi_region
  enable_log_file_validation    = true
  kms_key_id                    = aws_kms_key.cloudtrail[0].arn

  depends_on = [aws_s3_bucket_policy.cloudtrail]
}

resource "aws_s3_bucket" "cloudtrail" {
  count = var.cloudtrail.enabled ? 1 : 0

  bucket        = local.cloudtrail_name
  force_destroy = var.cloudtrail.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "cloudtrail" {
  count = var.cloudtrail.enabled ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail" {
  count = var.cloudtrail.enabled ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  rule {
    apply_server_side_encryption_by_default {
      kms_master_key_id = aws_kms_key.cloudtrail[0].arn
      sse_algorithm     = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail" {
  count = var.cloudtrail.enabled ? 1 : 0

  bucket                  = aws_s3_bucket.cloudtrail[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail" {
  count = var.cloudtrail.enabled ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  rule {
    id     = "expire-logs"
    status = "Enabled"
    expiration {
      days = var.cloudtrail.retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail" {
  count = var.cloudtrail.enabled ? 1 : 0

  bucket = aws_s3_bucket.cloudtrail[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail[0].arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
          }
        }
      },
    ]
  })
}

resource "aws_kms_key" "cloudtrail" {
  count = var.cloudtrail.enabled ? 1 : 0

  description             = "CloudTrail log encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_kms_alias" "cloudtrail" {
  count = var.cloudtrail.enabled ? 1 : 0

  name          = "alias/${local.name_prefix}-cloudtrail"
  target_key_id = aws_kms_key.cloudtrail[0].key_id
}

resource "aws_default_security_group" "this" {
  count = length(var.default_security_group_vpc_ids)

  vpc_id = var.default_security_group_vpc_ids[count.index]

  tags = merge(var.tags, {
    Name = "default-denied"
  })
}
