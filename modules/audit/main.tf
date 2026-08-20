data "aws_caller_identity" "current" {}

locals {
  log_bucket_name = var.log_bucket_name != "" ? var.log_bucket_name : join("-", [
    var.name_prefix,
    "logs",
    data.aws_caller_identity.current.account_id,
    var.region,
  ])
}

data "aws_organizations_organization" "org" {
  count = var.enabled && var.management_account ? 1 : 0
}

resource "aws_s3_bucket" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket              = local.log_bucket_name
  object_lock_enabled = true
  force_destroy       = false

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.logs[0].arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket                  = aws_s3_bucket.logs[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_object_lock_configuration" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id
  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket = aws_s3_bucket.logs[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid       = "AWSCloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.logs[0].arn
      },
      {
        Sid       = "AWSCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs[0].arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid       = "AWSConfigWrite"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs[0].arn}/AWSLogs/*/Config/*"
      },
      ], [
      for account_id in var.allowed_log_account_ids : {
        Sid       = "AWSConfigWrite${account_id}"
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.logs[0].arn}/AWSLogs/${account_id}/Config/*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = account_id }
        }
      }
    ])
  })
}

resource "aws_kms_key" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  description             = "${var.name_prefix} log encryption key"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = var.tags
}

resource "aws_kms_alias" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  name          = "alias/${var.name_prefix}-logs"
  target_key_id = aws_kms_key.logs[0].key_id
}

# note: organization cloudtrail enabled via control tower

# note: aws config enabled via control tower

resource "aws_s3_bucket" "log_access" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket        = "${local.log_bucket_name}-access"
  force_destroy = true

  tags = var.tags
}

resource "aws_s3_bucket_logging" "logs" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket        = aws_s3_bucket.logs[0].id
  target_bucket = aws_s3_bucket.log_access[0].id
  target_prefix = "log/"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_access" {
  count = var.enabled && var.management_account ? 1 : 0

  bucket = aws_s3_bucket.log_access[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_config_configuration_recorder" "this" {
  count = var.enabled && !var.management_account ? 1 : 0

  name     = "${var.name_prefix}-recorder"
  role_arn = aws_iam_role.config[0].arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_iam_role" "config" {
  count = var.enabled && !var.management_account ? 1 : 0

  name = "${var.name_prefix}-config"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "config.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "config" {
  count = var.enabled && !var.management_account ? 1 : 0

  role       = aws_iam_role.config[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
}

resource "aws_iam_role_policy" "config_delivery" {
  count = var.enabled && !var.management_account ? 1 : 0

  name = "config-s3-delivery"
  role = aws_iam_role.config[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:GetBucketAcl"]
        Resource = [
          "${var.log_bucket_arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/Config/*",
          var.log_bucket_arn,
        ]
      },
    ]
  })
}

resource "aws_config_delivery_channel" "this" {
  count = var.enabled && !var.management_account ? 1 : 0

  name           = "${var.name_prefix}-delivery"
  s3_bucket_name = var.log_bucket_name != "" ? var.log_bucket_name : local.log_bucket_name
  s3_key_prefix  = "AWSLogs/${data.aws_caller_identity.current.account_id}/Config"

  snapshot_delivery_properties {
    delivery_frequency = "Six_Hours"
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_config_config_rule" "managed" {
  for_each = var.enabled && !var.management_account ? toset(var.config_rules) : toset([])

  name = each.key
  source {
    owner             = "AWS"
    source_identifier = each.key
  }

  input_parameters = try(var.config_rule_parameters[each.key], null)

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_s3_bucket" "conformance_delivery" {
  count = var.enabled && !var.management_account ? 1 : 0

  bucket        = "${local.log_bucket_name}-conformance"
  force_destroy = true

  tags = var.tags
}

resource "aws_config_conformance_pack" "hipaa" {
  count = var.enabled && !var.management_account ? 1 : 0

  name               = "hipaa-security-best-practices"
  template_s3_uri    = "s3://aws-managed-config-conformance-packs-${var.region}/hipaa-security-best-practices.yaml"
  delivery_s3_bucket = aws_s3_bucket.conformance_delivery[0].bucket

  depends_on = [aws_config_configuration_recorder.this]
}
