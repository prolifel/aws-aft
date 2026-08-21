# Config Auto-Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attach automatic AWS Config remediation to managed rules on the account plane — 2 managed SSM docs, 1 custom ingress-swap automation — and remove the admin-port SCP denials.

**Architecture:** `modules/audit/` gains `remediation_rules` (rule → SSM doc + params), a generic `aws_config_remediation_configuration` per entry, plus a dedicated custom `aws_ssm_document` + `aws_iam_role` that swap public admin-port ingress to private CIDRs for `RESTRICTED_INCOMING_TRAFFIC`. `modules/scp/` drops both admin-port deny documents from the consolidated policy. All new resources gate on `enabled && !management_account` (account plane only).

**Tech Stack:** OpenTofu `>= 1.8.0`, AWS provider, `.tftest.hcl` with `mock_provider "aws" {}`.

---

### Task 1: Red tests — remediation surface

**Files:**
- Modify: `modules/hardened/tests/account_baseline.tftest.hcl` (management_plane + account_plane runs)

- [ ] **Step 1: Add account-plane remediation asserts**

In the `account_plane` run block, after the `scp_policy_id == ""` assert, insert:

```hcl
  assert {
    condition     = length(output.remediation_rule_names) == 3
    error_message = "account plane must attach remediations to the 3 default rules"
  }
  assert {
    condition     = output.custom_remediation_doc_name != ""
    error_message = "account plane must create the custom admin-port ingress remediation document"
  }
```

- [ ] **Step 2: Add management-plane assert**

In the `management_plane` run block, after the `scp_policy_id != ""` assert, insert:

```hcl
  assert {
    condition     = length(output.remediation_rule_names) == 0
    error_message = "management plane must not create remediations"
  }
```

- [ ] **Step 3: Run tests to verify failure**

Run: `cd modules/hardened && tofu test`
Expected: FAIL — `remediation_rule_names` output undeclared.

---

### Task 2: Remove admin-port SCP denials

**Files:**
- Modify: `modules/scp/main.tf`
- Modify: `modules/scp/variables.tf`

- [ ] **Step 1: Delete the two admin-port document blocks**

In `modules/scp/main.tf`, delete `data "aws_iam_policy_document" "deny_public_admin_ports_ipv4" { ... }` and `data "aws_iam_policy_document" "deny_public_admin_ports_ipv6" { ... }` in full (both dynamic-statement blocks). Leave the commented `require_mfa` block untouched.

- [ ] **Step 2: Remove their entries from the combined document**

In `data "aws_iam_policy_document" "combined"`, remove:

```hcl
    data.aws_iam_policy_document.deny_public_admin_ports_ipv4.json,
    data.aws_iam_policy_document.deny_public_admin_ports_ipv6.json,
```

- [ ] **Step 3: Delete the `admin_ports` variable**

In `modules/scp/variables.tf`, delete the `variable "admin_ports" { ... }` block (lines 29-33).

- [ ] **Step 4: Validate**

Run: `cd modules/scp && tofu init -backend=false && tofu validate`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add modules/scp/main.tf modules/scp/variables.tf
git commit -m "refactor(scp): remove admin-port ingress denials"
```

---

### Task 3: Audit module — remediation resources

**Files:**
- Modify: `modules/audit/main.tf`
- Modify: `modules/audit/variables.tf`
- Modify: `modules/audit/outputs.tf`

- [ ] **Step 1: Extend locals**

In `modules/audit/main.tf`, extend the existing `locals` block (after `log_bucket_name`) with:

```hcl
  remediation_private_cidrs = ["10.0.0.0/8", "172.16.0.0/16", "192.168.0.0/24"]
  remediation_admin_ports   = [22, 3389, 1433, 3306]
  remediation_entries = {
    for k, v in var.remediation_rules : k => v
    if var.enabled && !var.management_account && contains(var.config_rules, k)
  }
  restricted_ingress_remediation = var.enabled && !var.management_account && contains(var.config_rules, "RESTRICTED_INCOMING_TRAFFIC")
```

- [ ] **Step 2: Add generic remediation resource**

After `resource "aws_config_config_rule" "managed"`, insert:

```hcl
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
```

- [ ] **Step 3: Add custom SSM document**

After the generic remediation resource, insert:

```hcl
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
```

- [ ] **Step 4: Add remediation role + policy**

After the SSM document, insert:

```hcl
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
        Effect   = "Allow"
        Action   = [
          "ec2:DescribeSecurityGroups",
          "ec2:RevokeSecurityGroupIngress",
          "ec2:AuthorizeSecurityGroupIngress",
        ]
        Resource = "*"
      },
    ]
  })
}
```

- [ ] **Step 5: Add dedicated RESTRICTED_INCOMING_TRAFFIC remediation**

After the IAM policy, insert:

```hcl
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
```

- [ ] **Step 6: Add `remediation_rules` variable**

In `modules/audit/variables.tf`, after `config_rule_parameters`, insert:

```hcl
variable "remediation_rules" {
  description = "AWS Config auto-remediation per managed rule: SSM document, automatic flag, static and resource parameters."
  type = map(object({
    ssm_document        = string
    automatic           = optional(bool, true)
    static_parameters   = optional(map(string), {})
    resource_parameters = optional(map(string), {})
  }))
  default = {
    ENCRYPTED_VOLUMES = {
      ssm_document = "AWSConfigRemediation-EnableEbsEncryptionByDefault"
    }
    S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED = {
      ssm_document        = "AWS-EnableS3BucketEncryption"
      resource_parameters = { BucketName = "RESOURCE_ID" }
      static_parameters   = { SSEAlgorithm = "AES256" }
    }
  }
}
```

- [ ] **Step 7: Add `RESTRICTED_INCOMING_TRAFFIC` to rule defaults**

In `modules/audit/variables.tf`, append `"RESTRICTED_INCOMING_TRAFFIC"` to the `config_rules` default list (13 rules).

- [ ] **Step 8: Add outputs**

Append to `modules/audit/outputs.tf`:

```hcl
output "remediation_rule_names" {
  description = "Names of rules with attached remediation."
  value       = var.enabled && !var.management_account ? concat(keys(local.remediation_entries), local.restricted_ingress_remediation ? ["RESTRICTED_INCOMING_TRAFFIC"] : []) : []
}

output "custom_remediation_doc_name" {
  description = "Name of the custom admin-port ingress remediation document."
  value       = var.enabled && !var.management_account ? aws_ssm_document.remediation_swap_public_admin_ingress[0].name : ""
}
```

- [ ] **Step 9: Validate**

Run: `cd modules/audit && tofu init -backend=false && tofu validate`
Expected: PASS.

- [ ] **Step 10: Commit**

```bash
git add modules/audit/main.tf modules/audit/variables.tf modules/audit/outputs.tf
git commit -m "feat(audit): attach Config auto-remediation and custom ingress-swap document"
```

---

### Task 4: Hardened module — pass through

**Files:**
- Modify: `modules/hardened/main.tf`
- Modify: `modules/hardened/variables.tf`
- Modify: `modules/hardened/outputs.tf`

- [ ] **Step 1: Add pass-through variable**

In `modules/hardened/variables.tf`, after `config_rule_parameters`, insert the same `remediation_rules` variable definition as Task 3 Step 6 (identical type and default map).

- [ ] **Step 2: Add `RESTRICTED_INCOMING_TRAFFIC` to hardened rule defaults**

Append `"RESTRICTED_INCOMING_TRAFFIC"` to the `config_rules` default list in `modules/hardened/variables.tf` (13 rules).

- [ ] **Step 3: Wire the audit call**

In `modules/hardened/main.tf`, in `module "audit"`, after `config_rule_parameters = var.config_rule_parameters`, add:

```hcl
  remediation_rules        = var.remediation_rules
```

- [ ] **Step 4: Add outputs**

In `modules/hardened/outputs.tf`, after the `conformance_pack_name` output, add:

```hcl
output "remediation_rule_names" {
  description = "Names of rules with attached remediation."
  value       = module.audit.remediation_rule_names
}

output "custom_remediation_doc_name" {
  description = "Name of the custom admin-port ingress remediation document."
  value       = module.audit.custom_remediation_doc_name
}
```

- [ ] **Step 5: Commit**

```bash
git add modules/hardened/main.tf modules/hardened/variables.tf modules/hardened/outputs.tf
git commit -m "feat(hardened): pass through Config remediation settings"
```

---

### Task 5: Green verification

**Files:** none modified (verification only)

- [ ] **Step 1: Run the test suite**

Run: `cd modules/hardened && tofu test`
Expected: PASS — all 3 runs, including the new remediation asserts.

- [ ] **Step 2: Format check**

Run: `cd modules/hardened && tofu fmt -check ..`
Expected: no unformatted files. If any are listed, run `tofu fmt` on them and commit as `chore: format`.

- [ ] **Step 3: Final commit if Step 2 changed files**

```bash
git add -A
git commit -m "chore: format after config remediation changes"
```
