# Design: AWS Config managed-rule auto remediation

Date: 2026-08-20
Status: Approved for implementation
Scope: aws-hardened module repo

## Problem

The account plane deploys 12 AWS Config managed rules (`modules/audit/main.tf:236`),
but nothing remediates noncompliant resources. Encryption and SG-ingress
violations are flagged and left until a human fixes them.

Goal: attach automatic remediation to a curated set of managed rules, using
AWS-provided SSM automation documents and the Config service-linked role —
no new IAM, no custom documents.

## Decision

1. **`modules/audit/` — new `remediation_rules` variable** (map keyed by Config
   rule name):

```hcl
variable "remediation_rules" {
  type = map(object({
    ssm_document        = string
    automatic           = optional(bool, true)
    static_parameters   = optional(map(string), {})
    resource_parameters = optional(map(string), {})
  }))
  default = {
    ENCRYPTED_VOLUMES = {
      ssm_document        = "AWS-EncryptEBSVolume"
      resource_parameters = { VolumeId = "RESOURCE_ID" }
    }
    S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED = {
      ssm_document        = "AWS-ConfigureS3BucketEncryption"
      resource_parameters = { BucketName = "RESOURCE_ID" }
      static_parameters   = { SSEAlgorithm = "AES256" }
    }
    RDS_STORAGE_ENCRYPTED = {
      ssm_document        = "AWS-EnableRDSInstanceStorageEncryption"
      resource_parameters = { DBInstanceIdentifier = "RESOURCE_ID" }
    }
    RESTRICTED_INCOMING_TRAFFIC = {
      ssm_document        = "AWS-RestrictEC2SecurityGroupIngress"
      resource_parameters = { SecurityGroupId = "RESOURCE_ID" }
      static_parameters   = {
        whitelistedCidr = "10.0.0.0/8,172.16.0.0/16,192.168.0.0/24"
      }
    }
  }
}
```

   Note: `RESTRICTED_INCOMING_TRAFFIC` has no safe default whitelist, so the
   default CIDRs above are the agreed private-range policy
   (`10.0.0.0/8`, `172.16.0.0/16`, `192.168.0.0/24`).

2. **`modules/audit/main.tf` — remediation resource:**

```hcl
resource "aws_config_remediation_configuration" "this" {
  for_each = var.enabled && !var.management_account ? local.remediation_entries : {}

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
```

   `local.remediation_entries` filters `remediation_rules` to keys present in
   `var.config_rules` — a remediation without its rule is skipped silently
   rather than erroring (mirrors the per-account gating). Remediation runs
   under the Config service-linked role; no IAM additions.

3. **Rule default:** add `RESTRICTED_INCOMING_TRAFFIC` to `config_rules`
   defaults in both `modules/audit/variables.tf` and
   `modules/hardened/variables.tf` (13 rules on the account plane).

4. **`modules/hardened/`:** pass through `remediation_rules` to
   `module.audit`; new output `remediation_rule_names` (audit) surfaced
   through hardened.

5. **Tests:** `modules/hardened/tests/account_baseline.tftest.hcl` — account
   plane run asserts `length(output.remediation_rule_names) == 4`; management
   plane run asserts `== 0`.

## Caveat

SSM document names and parameter keys above are best-known AWS-managed values.
During implementation planning, verify each against AWS documentation; if any
managed doc does not exist (e.g. the RDS encryption doc), that entry is
dropped from the defaults and the user supplies the correct doc name. `tofu
validate` cannot catch a wrong doc ARN/name — that surfaces at apply time.

## Non-goals

- No custom SSM documents.
- No IAM role creation for remediation.
- No remediation on the management plane.
- No manual-mode remediation.

## Verification

- `cd modules/hardened && tofu test` — 3 runs pass, new remediation asserts.
- `cd modules/scp && tofu init -backend=false && tofu validate` (unchanged).
- `tofu fmt` clean.

## Amendment 1 (2026-08-20): verified doc names + custom ingress-swap doc + SCP admin-port removal

Approved deltas after live verification against SSM (us-east-1) and design review:

1. **Verified managed documents (replaces the caveat):**
   - `ENCRYPTED_VOLUMES` → `AWSConfigRemediation-EnableEbsEncryptionByDefault` (no parameters).
   - `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED` → `AWS-EnableS3BucketEncryption`
     (`BucketName` ← resource value, `SSEAlgorithm` = `AES256`).
   - `RDS_STORAGE_ENCRYPTED` → **dropped from defaults** — no AWS-managed
     automation exists for RDS storage encryption; caller supplies a doc name
     in `remediation_rules` if wanted.
2. **Custom SSM document `remediation-swap-public-admin-ingress`** for
   `RESTRICTED_INCOMING_TRAFFIC` (account plane only):
   - `aws_ssm_document` with one `aws:executeScript` (Python) step.
   - Parameters: `GroupId`, `AutomationAssumeRole`, `PrivateCidrs`
     (default `10.0.0.0/8,172.16.0.0/16,192.168.0.0/24`), `AdminPorts`
     (default `22,3389,1433,3306`).
   - For each IPv4 ingress permission containing `0.0.0.0/0` whose
     protocol/port range is `-1` (all) or overlaps any admin port: revoke the
     rule, then re-authorize the same protocol + port range from each private
     CIDR, skipping when an identical rule already exists (idempotent, re-run
     safe). IPv6 (`::/0`) public admin-port rules: revoked without
     replacement. Non-admin-port public rules: untouched.
   - `aws_iam_role.remediation` (trust `ssm.amazonaws.com`) with inline policy
     `ec2:DescribeSecurityGroups`, `ec2:RevokeSecurityGroupIngress`,
     `ec2:AuthorizeSecurityGroupIngress`.
   - `RESTRICTED_INCOMING_TRAFFIC` remediation entry uses the custom doc:
     static `AutomationAssumeRole` + `PrivateCidrs` + `AdminPorts`, resource
     `SecurityGroupId = RESOURCE_ID`.
3. **SCP change (`modules/scp/main.tf`):** remove the admin-port denials
   entirely — delete both `deny_public_admin_ports_ipv4` (`0.0.0.0/0`) and
   `deny_public_admin_ports_ipv6` (`::/0`) data documents and their entries in
   `combined.source_policy_documents`; delete the now-unused `admin_ports`
   variable. Tradeoff accepted: public admin ports are no longer blocked at
   org level; Config auto-remediation (account plane) is the control.
4. **Tests:** account-plane run asserts 4 remediations
   (`ENCRYPTED_VOLUMES`, `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED`,
   `RESTRICTED_INCOMING_TRAFFIC`, plus the custom-doc SSM resource exists);
   management-plane run asserts none.
