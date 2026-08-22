data "aws_caller_identity" "current" {}

locals {
  log_bucket_name = var.log_bucket_name != "" ? var.log_bucket_name : join("-", [
    var.name_prefix,
    "logs",
    data.aws_caller_identity.current.account_id,
    var.region,
  ])

  remediation_private_cidrs = ["10.0.0.0/8", "172.16.0.0/16", "192.168.0.0/24"]
  remediation_admin_ports   = [22, 3389, 1433, 3306]
  remediation_entries = {
    for k, v in var.remediation_rules : k => merge(v, {
      static_parameters = merge(v.static_parameters, {
        AutomationAssumeRole = aws_iam_role.remediation[0].arn
      })
    })
    if var.enabled && !var.management_account && contains(var.config_rules, k)
  }
  restricted_ingress_remediation = var.enabled && !var.management_account && contains(var.config_rules, "RESTRICTED_INCOMING_TRAFFIC")
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

resource "aws_config_remediation_configuration" "this" {
  for_each = local.remediation_entries

  config_rule_name = aws_config_config_rule.managed[each.key].name
  target_type      = "SSM_DOCUMENT"
  target_id        = each.value.ssm_document
  automatic        = each.value.automatic

  dynamic "parameter" {
    for_each = each.value.static_parameters
    content {
      name         = parameter.key
      static_value = parameter.value
    }
  }

  dynamic "parameter" {
    for_each = each.value.resource_parameters
    content {
      name           = parameter.key
      resource_value = parameter.value
    }
  }

  depends_on = [aws_config_configuration_recorder.this]
}

resource "aws_ssm_document" "remediation_swap_public_admin_ingress" {
  count = var.enabled && !var.management_account ? 1 : 0

  name            = "${var.name_prefix}-swap-public-admin-ingress"
  document_type   = "Automation"
  document_format = "YAML"

  content = <<-EOT
    schemaVersion: '2.2'
    description: Revoke public ingress covering admin ports and re-authorize from private CIDRs.
    assumeRole: "{{ AutomationAssumeRole }}"
    parameters:
      GroupId:
        type: String
        description: Security group ID to remediate.
      AutomationAssumeRole:
        type: String
        description: ARN of the role the automation assumes.
      PrivateCidrs:
        type: String
        default: "10.0.0.0/8,172.16.0.0/16,192.168.0.0/24"
        description: Comma-separated private IPv4 CIDRs to authorize.
      AdminPorts:
        type: String
        default: "22,3389,1433,3306"
        description: Comma-separated admin port numbers.
    mainSteps:
      - name: SwapPublicAdminIngress
        action: aws:executeScript
        inputs:
          Runtime: python3.12
          Handler: swap_public_admin_ingress
          InputPayload:
            GroupId: "{{ GroupId }}"
            PrivateCidrs: "{{ PrivateCidrs }}"
            AdminPorts: "{{ AdminPorts }}"
          Script: |
            import boto3

            def swap_public_admin_ingress(events, context):
                ec2 = boto3.client('ec2')
                group_id = events['GroupId']
                private_cidrs = [c.strip() for c in events['PrivateCidrs'].split(',') if c.strip()]
                admin_ports = [int(p) for p in events['AdminPorts'].split(',')]

                def overlaps_admin_ports(perm):
                    proto = perm.get('IpProtocol', '-1')
                    frm = perm.get('FromPort')
                    to = perm.get('ToPort')
                    if proto == '-1':
                        return True
                    if proto not in ('tcp', 'udp'):
                        return False
                    if frm is None:
                        return True
                    return any(frm <= p <= to for p in admin_ports)

                def rule_exists(perms, proto, frm, to, cidr):
                    for p in perms:
                        if p.get('IpProtocol') != proto or p.get('FromPort') != frm or p.get('ToPort') != to:
                            continue
                        if any(r.get('CidrIp') == cidr for r in p.get('IpRanges', [])):
                            return True
                    return False

                def current_perms():
                    return ec2.describe_security_groups(GroupIds=[group_id])['SecurityGroups'][0]['IpPermissions']

                replaced = 0
                for perm in current_perms():
                    if not overlaps_admin_ports(perm):
                        continue
                    public_v4 = [r for r in perm.get('IpRanges', []) if r.get('CidrIp') == '0.0.0.0/0']
                    public_v6 = [r for r in perm.get('Ipv6Ranges', []) if r.get('CidrIpv6') == '::/0']
                    if not public_v4 and not public_v6:
                        continue
                    base = {k: v for k, v in perm.items() if k not in ('IpRanges', 'Ipv6Ranges', 'PrefixListIds', 'UserIdGroupPairs')}
                    revoke_perm = dict(base)
                    if public_v4:
                        revoke_perm['IpRanges'] = public_v4
                    if public_v6:
                        revoke_perm['Ipv6Ranges'] = public_v6
                    ec2.revoke_security_group_ingress(GroupId=group_id, IpPermissions=[revoke_perm])
                    replaced += 1
                    if public_v4:
                        for cidr in private_cidrs:
                            perms = current_perms()
                            if rule_exists(perms, base.get('IpProtocol'), base.get('FromPort'), base.get('ToPort'), cidr):
                                continue
                            new_perm = dict(base)
                            new_perm['IpRanges'] = [{'CidrIp': cidr}]
                            ec2.authorize_security_group_ingress(GroupId=group_id, IpPermissions=[new_perm])
                return {'ReplacedRules': replaced}
        timeoutSeconds: 300
        outputs:
          - Name: ReplacedRules
            Selector: $.Payload.ReplacedRules
            Type: Integer
  EOT
}

resource "aws_iam_role" "remediation" {
  count = var.enabled && !var.management_account ? 1 : 0

  name = "${var.name_prefix}-config-remediation"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Service = "ssm.amazonaws.com" }
        Action    = "sts:AssumeRole"
      },
    ]
  })
}

resource "aws_iam_role_policy" "remediation" {
  count = var.enabled && !var.management_account ? 1 : 0

  name = "config-remediation"
  role = aws_iam_role.remediation[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeSecurityGroups",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:EnableEbsEncryptionByDefault",
          "ec2:GetEbsEncryptionByDefault",
          "s3:PutBucketEncryption",
          "s3:GetEncryptionConfiguration",
        ]
        Resource = "*"
      },
    ]
  })
}

resource "aws_config_remediation_configuration" "restricted_ingress" {
  count = local.restricted_ingress_remediation ? 1 : 0

  config_rule_name = aws_config_config_rule.managed["RESTRICTED_INCOMING_TRAFFIC"].name
  target_type      = "SSM_DOCUMENT"
  target_id        = aws_ssm_document.remediation_swap_public_admin_ingress[0].name
  automatic        = true

  parameter {
    name           = "GroupId"
    resource_value = "RESOURCE_ID"
  }
  parameter {
    name         = "AutomationAssumeRole"
    static_value = aws_iam_role.remediation[0].arn
  }
  parameter {
    name         = "PrivateCidrs"
    static_value = join(",", local.remediation_private_cidrs)
  }
  parameter {
    name         = "AdminPorts"
    static_value = join(",", [for p in local.remediation_admin_ports : tostring(p)])
  }

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
