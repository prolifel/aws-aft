# Management-Plane Break-Glass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Break-glass credentials live in the management account; a designated IAM user (MFA) assumes a management-account `break-glass` role, which can assume a `break-glass` role in every child account to run read-only recovery actions and create IAM users with attached policies.

**Architecture:** Three cooperating changes. `modules/identity/` creates the break-glass role in both planes (management plane: user+MFA trust, assume-children policy; child plane: trusts the management role, narrow read-only + `iam:CreateUser`/`CreateLoginProfile`/`AttachUserPolicy`). `modules/scp/` exempts a list of break-glass ARNs from the user-creation, inline-policy, and MFA denials. `modules/hardened/` derives the child account list and role ARNs from `aws_organizations_organization` (management plane only) and wires them to both modules; the management root publishes its role ARN in the handoff `config.json` so per-account pipeline roots can trust it.

**Tech Stack:** OpenTofu >= 1.8.0, AWS provider 6.58.0 (pinned), HCL, `tofu test` with `mock_provider`.

**Spec:** `docs/superpowers/specs/2026-08-19-break-glass-mgmt-design.md`

---

## File Structure

- `modules/scp/variables.tf` — replace `break_glass_role_arn` with `break_glass_exempt_arns` (list).
- `modules/scp/main.tf` — exemption conditions in `deny_iam_user_creations`, `deny_iam_user_inline_policies`, `require_mfa`.
- `modules/identity/variables.tf` — add `break_glass_user_name`, `break_glass_mgmt_role_arn`, `break_glass_target_account_ids`.
- `modules/identity/main.tf` — role in both planes, plane-specific trust/policies, IAM user (mgmt), alerts on both planes.
- `modules/identity/outputs.tf` — add `break_glass_user_name`.
- `modules/hardened/variables.tf` — remove `break_glass_role_arn`, add `break_glass_user_name`, `break_glass_mgmt_role_arn`.
- `modules/hardened/main.tf` — org data source (mgmt only), derived exemption list, module wiring.
- `modules/hardened/outputs.tf` — add `break_glass_user_name`.
- `modules/hardened/tests/account_baseline.tftest.hcl` — mock org + caller identity, new assertions.
- `01-management-init-role-and-hardening/variables.tf` — remove `break_glass_role_arn`, add `break_glass_user_name`.
- `01-management-init-role-and-hardening/main.tf` — pass user name, publish `break_glass_mgmt_role_arn` in `config.json`.
- `pipeline/account-hardening/main.tf` — pass `break_glass_mgmt_role_arn` from config.

**Deviation from spec (flagged):** spec says empty `break_glass_mgmt_role_arn` disables child-plane break-glass creation. Plan keeps the child role created with the existing deny-all trust when the ARN is empty, so `examples/basic/` and the existing account-plane test keep working. The ARN is always populated in practice once `01-management` applies (via `config.json`).

---

### Task 1: SCP exemption list

**Files:**
- Modify: `modules/scp/variables.tf:23-28`
- Modify: `modules/scp/main.tf:12-17`, `modules/scp/main.tf:95-100`, `modules/scp/main.tf:29-38`

- [ ] **Step 1: Replace the `break_glass_role_arn` variable**

In `modules/scp/variables.tf`, replace the `break_glass_role_arn` block:

```hcl
variable "break_glass_exempt_arns" {
  description = "ARNs of break-glass roles exempted from user-creation, inline-policy, and MFA SCP denials. Empty disables the exception."
  type        = list(string)
  default     = []
}
```

- [ ] **Step 2: Update the user-creation denial condition**

In `modules/scp/main.tf`, in `data "aws_iam_policy_document" "deny_iam_user_creations"`, replace the dynamic condition block with:

```hcl
    dynamic "condition" {
      for_each = length(var.break_glass_exempt_arns) > 0 ? [1] : []
      content {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = var.break_glass_exempt_arns
      }
    }
```

- [ ] **Step 3: Update the inline-policy denial condition**

In `modules/scp/main.tf`, in `data "aws_iam_policy_document" "deny_iam_user_inline_policies"`, apply the same replacement (same dynamic condition as Step 2).

- [ ] **Step 4: Add the exemption to the MFA denial**

In `modules/scp/main.tf`, in `data "aws_iam_policy_document" "require_mfa"`, after the existing `BoolIfExists` condition block, add:

```hcl
    dynamic "condition" {
      for_each = length(var.break_glass_exempt_arns) > 0 ? [1] : []
      content {
        test     = "ArnNotEquals"
        variable = "aws:PrincipalArn"
        values   = var.break_glass_exempt_arns
      }
    }
```

`ArnNotEquals` with multiple values denies unless the principal is one of the listed ARNs; the extra condition on `require_mfa` is ANDed with the MFA check, so exempt roles bypass the MFA denial (role chaining does not carry MFA context).

- [ ] **Step 5: Verify the module still parses**

Run: `cd modules/scp && tofu init -backend=false && tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add modules/scp/variables.tf modules/scp/main.tf
git commit -m "refactor(scp): accept break-glass exemption ARN list"
```

---

### Task 2: Identity module variables

**Files:**
- Modify: `modules/identity/variables.tf` (after the `break_glass_policy` block, line 93)

- [ ] **Step 1: Add the three new variables**

In `modules/identity/variables.tf`, after the `break_glass_policy` block, add:

```hcl
variable "break_glass_user_name" {
  description = "Name of the management-account IAM user allowed to assume the break-glass role."
  type        = string
  default     = "break-glass-user"
}

variable "break_glass_mgmt_role_arn" {
  description = "ARN of the management-account break-glass role; used as the child-account role trust principal. Empty keeps the child-account role untrusted."
  type        = string
  default     = ""
}

variable "break_glass_target_account_ids" {
  description = "Child account IDs whose break-glass roles the management-account break-glass role may assume. Empty on the child plane."
  type        = list(string)
  default     = []
}
```

- [ ] **Step 2: Verify**

Run: `cd modules/identity && tofu init -backend=false && tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add modules/identity/variables.tf
git commit -m "feat(identity): add break-glass management-plane variables"
```

---

### Task 3: Identity module resources

**Files:**
- Modify: `modules/identity/main.tf` (locals at lines 2-22, role at 93-100, role policy at 103-109, SNS at 111-116, topic policy at 119-135, event rule at 137-152, event target at 154-160)
- Modify: `modules/identity/outputs.tf` (after line 23)

- [ ] **Step 1: Extend locals**

In `modules/identity/main.tf`, replace the `break_glass_policy` local (lines 7-22) with:

```hcl
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
          "iam:CreateUser",
          "iam:CreateLoginProfile",
          "iam:AttachUserPolicy",
        ]
        Resource = "*"
      },
    ]
  })
  break_glass_mgmt_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "BreakGlassReadOnly"
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
      {
        Sid      = "BreakGlassAssumeChildren"
        Effect   = "Allow"
        Action   = ["sts:AssumeRole"]
        Resource = [for id in var.break_glass_target_account_ids : "arn:aws:iam::${id}:role/${var.break_glass_role_name}"]
      },
    ]
  })
  break_glass_mgmt_enabled   = var.enabled && var.management_account
  break_glass_account_enabled = var.enabled && !var.management_account
```

Note: this narrows the existing wildcard `"iam:Create*"` to the three explicit actions (no `iam:CreateAccessKey`).

- [ ] **Step 2: Rework the role for both planes**

Replace the `aws_iam_role.break_glass` resource (currently `count = var.enabled && !var.management_account ? 1 : 0`) with:

```hcl
resource "aws_iam_role" "break_glass" {
  count = var.enabled ? 1 : 0

  name = var.break_glass_role_name
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = var.management_account ? [{
      Sid       = "AllowBreakGlassUser"
      Effect    = "Allow"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/${var.break_glass_user_name}" }
      Action    = ["sts:AssumeRole"]
      Condition = { Bool = { "aws:MultiFactorAuthPresent" = "true" } }
    }] : var.break_glass_mgmt_role_arn != "" ? [{
      Sid       = "AllowMgmtBreakGlass"
      Effect    = "Allow"
      Principal = { AWS = var.break_glass_mgmt_role_arn }
      Action    = ["sts:AssumeRole"]
    }] : []
  })
  max_session_duration = 3600

  tags = var.tags
}
```

- [ ] **Step 3: Split role policies per plane**

Replace the existing `aws_iam_role_policy.break_glass` (count `var.enabled && !var.management_account ? 1 : 0`) with two resources:

```hcl
resource "aws_iam_role_policy" "break_glass" {
  count = local.break_glass_account_enabled ? 1 : 0

  name   = "break-glass-minimal"
  role   = aws_iam_role.break_glass[0].id
  policy = local.break_glass_policy
}

resource "aws_iam_role_policy" "break_glass_mgmt" {
  count = local.break_glass_mgmt_enabled ? 1 : 0

  name   = "break-glass-mgmt"
  role   = aws_iam_role.break_glass[0].id
  policy = local.break_glass_mgmt_policy
}
```

- [ ] **Step 4: Create the management-account IAM user**

After the `aws_iam_role_policy.break_glass_mgmt` resource, add:

```hcl
resource "aws_iam_user" "break_glass" {
  count = local.break_glass_mgmt_enabled ? 1 : 0

  name = var.break_glass_user_name
  tags = var.tags
}
```

Password and MFA enrollment are operator-managed in the console (out-of-band, per spec).

- [ ] **Step 5: Enable alerts on both planes**

Change the `count` on these four resources from `var.enabled && !var.management_account ? 1 : 0` to `var.enabled ? 1 : 0`:
- `aws_sns_topic.break_glass`
- `aws_sns_topic_policy.break_glass`
- `aws_cloudwatch_event_rule.break_glass_assume`
- `aws_cloudwatch_event_target.break_glass_assume`

- [ ] **Step 6: Add the user output**

In `modules/identity/outputs.tf`, after `break_glass_sns_topic_arn`, add:

```hcl
output "break_glass_user_name" {
  description = "Name of the management-account break-glass IAM user."
  value       = try(aws_iam_user.break_glass[0].name, "")
}
```

- [ ] **Step 7: Verify**

Run: `cd modules/identity && tofu init -backend=false && tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 8: Commit**

```bash
git add modules/identity/main.tf modules/identity/outputs.tf
git commit -m "feat(identity): create break-glass role in both planes with mgmt user"
```

---

### Task 4: Hardened module wiring

**Files:**
- Modify: `modules/hardened/variables.tf:158-162`
- Modify: `modules/hardened/main.tf` (top locals, `module "identity"` at 18-28, `module "scp"` at 30-37)
- Modify: `modules/hardened/outputs.tf` (after line 22)

- [ ] **Step 1: Swap the variable**

In `modules/hardened/variables.tf`, replace the `break_glass_role_arn` block with:

```hcl
variable "break_glass_user_name" {
  description = "Name of the management-account IAM user allowed to assume the break-glass role."
  type        = string
  default     = "break-glass-user"
}

variable "break_glass_mgmt_role_arn" {
  description = "ARN of the management-account break-glass role. Child-plane callers must set this so per-account roles trust it. Empty on the management plane derives it from the org."
  type        = string
  default     = ""
}
```

- [ ] **Step 2: Add org data source and derived locals**

At the top of `modules/hardened/main.tf` (before `module "encryption"`), add:

```hcl
data "aws_caller_identity" "current" {}

data "aws_organizations_organization" "org" {
  count = var.management_account ? 1 : 0
}

locals {
  child_account_ids = var.management_account ? [
    for a in data.aws_organizations_organization.org[0].accounts :
    a.id
    if a.id != data.aws_caller_identity.current.account_id
  ] : []
  mgmt_break_glass_role_arn = var.management_account
    ? "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.break_glass_role_name}"
    : var.break_glass_mgmt_role_arn
  break_glass_exempt_arns = var.management_account
    ? concat(
        [for id in local.child_account_ids : "arn:aws:iam::${id}:role/${var.break_glass_role_name}"],
        [local.mgmt_break_glass_role_arn],
      )
    : []
}
```

- [ ] **Step 3: Wire identity module**

In `modules/hardened/main.tf`, in `module "identity"`, replace `break_glass_role_name = var.break_glass_role_name` with:

```hcl
  break_glass_role_name          = var.break_glass_role_name
  break_glass_user_name          = var.break_glass_user_name
  break_glass_mgmt_role_arn      = local.mgmt_break_glass_role_arn
  break_glass_target_account_ids = local.child_account_ids
```

- [ ] **Step 4: Wire scp module**

In `modules/hardened/main.tf`, in `module "scp"`, remove `break_glass_role_arn = var.break_glass_role_arn` and add:

```hcl
  break_glass_exempt_arns = local.break_glass_exempt_arns
```

- [ ] **Step 5: Add the user output**

In `modules/hardened/outputs.tf`, after `break_glass_sns_topic_arn`, add:

```hcl
output "break_glass_user_name" {
  description = "Name of the management-account break-glass IAM user."
  value       = module.identity.break_glass_user_name
}
```

- [ ] **Step 6: Verify**

Run: `cd modules/hardened && tofu init -backend=false && tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 7: Commit**

```bash
git add modules/hardened/variables.tf modules/hardened/main.tf modules/hardened/outputs.tf
git commit -m "feat(hardened): derive org-wide break-glass exemptions"
```

---

### Task 5: Management root

**Files:**
- Modify: `01-management-init-role-and-hardening/variables.tf:37-42`
- Modify: `01-management-init-role-and-hardening/main.tf:13`, `01-management-init-role-and-hardening/main.tf:61-66`

- [ ] **Step 1: Swap the variable**

In `01-management-init-role-and-hardening/variables.tf`, replace the `break_glass_role_arn` block with:

```hcl
variable "break_glass_user_name" {
  description = "Name of the management-account IAM user allowed to assume the break-glass role."
  type        = string
  default     = "break-glass-user"
}
```

- [ ] **Step 2: Pass the user name**

In `01-management-init-role-and-hardening/main.tf`, in `module "hardened"`, replace `break_glass_role_arn              = var.break_glass_role_arn` with:

```hcl
  break_glass_user_name              = var.break_glass_user_name
```

- [ ] **Step 3: Publish the role ARN for child roots**

In `01-management-init-role-and-hardening/main.tf`, in the `aws_s3_object.config` content (`config.json`), add after `log_bucket_arn`:

```hcl
    break_glass_mgmt_role_arn = module.hardened.break_glass_role_arn
```

- [ ] **Step 4: Verify**

Run: `cd 01-management-init-role-and-hardening && tofu init -backend=false && tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add 01-management-init-role-and-hardening/variables.tf 01-management-init-role-and-hardening/main.tf
git commit -m "feat(01-management): publish break-glass role ARN to child accounts"
```

---

### Task 6: Per-account pipeline root

**Files:**
- Modify: `pipeline/account-hardening/main.tf` (module call at lines 9-18)

- [ ] **Step 1: Pass the management role ARN**

In `pipeline/account-hardening/main.tf`, in `module "hardened"`, add:

```hcl
  break_glass_mgmt_role_arn = local.config.break_glass_mgmt_role_arn
```

- [ ] **Step 2: Verify**

Run: `cd pipeline/account-hardening && tofu init -backend=false && tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Commit**

```bash
git add pipeline/account-hardening/main.tf
git commit -m "feat(account-hardening): trust management break-glass role"
```

---

### Task 7: Test assertions

**Files:**
- Modify: `modules/hardened/tests/account_baseline.tftest.hcl`

- [ ] **Step 1: Mock org and caller identity**

In `modules/hardened/tests/account_baseline.tftest.hcl`, inside the `mock_provider "aws"` block, after the `mock_data "aws_iam_policy_document"` block, add:

```hcl
  mock_data "aws_organizations_organization" {
    defaults = {
      accounts = [
        {
          id     = "123456789012"
          arn    = "arn:aws:organizations::123456789012:account/o-test/123456789012"
          email  = "mgmt@example.com"
          name   = "management"
          status = "ACTIVE"
        },
        {
          id     = "210987654321"
          arn    = "arn:aws:organizations::123456789012:account/o-test/210987654321"
          email  = "child@example.com"
          name   = "child"
          status = "ACTIVE"
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
```

- [ ] **Step 2: Add management-plane assertions**

In the `run "management_plane"` block, after the existing assertions, add:

```hcl
  assert {
    condition     = output.break_glass_role_arn != ""
    error_message = "management plane must create the break-glass role"
  }
  assert {
    condition     = output.break_glass_user_name == "break-glass-user"
    error_message = "management plane must create the break-glass IAM user"
  }
  assert {
    condition     = can(regex("user/break-glass-user", module.identity.aws_iam_role.break_glass[0].assume_role_policy))
    error_message = "mgmt break-glass role must trust the designated IAM user"
  }
  assert {
    condition     = can(regex("arn:aws:iam::210987654321:role/break-glass", module.identity.aws_iam_role_policy.break_glass_mgmt[0].policy))
    error_message = "mgmt break-glass role must be able to assume child break-glass roles"
  }
```

- [ ] **Step 3: Add account-plane variables and assertions**

In the `run "account_plane"` block, add to `variables`:

```hcl
    break_glass_mgmt_role_arn = "arn:aws:iam::123456789012:role/break-glass"
```

After the existing assertions, add:

```hcl
  assert {
    condition     = can(regex("arn:aws:iam::123456789012:role/break-glass", module.identity.aws_iam_role.break_glass[0].assume_role_policy))
    error_message = "child break-glass role must trust the management break-glass role"
  }
  assert {
    condition     = can(regex("iam:CreateUser", module.identity.aws_iam_role_policy.break_glass[0].policy))
    error_message = "child break-glass role must be able to create IAM users"
  }
  assert {
    condition     = !can(regex("iam:CreateAccessKey", module.identity.aws_iam_role_policy.break_glass[0].policy))
    error_message = "child break-glass role must not create access keys"
  }
```

- [ ] **Step 4: Run the suite**

Run: `cd modules/hardened && tofu init -backend=false && tofu test`
Expected: all runs PASS.

Note: SCP policy content is mocked by `mock_data "aws_iam_policy_document"` (returns `{"Statement":[]}`), so exemption rendering inside the SCP JSON is not assertable in `tofu test`. The exemption wiring is verified by Task 7 assertions (role ARNs present in mgmt policy + 5 SCPs still created) and must be sanity-checked against a real plan during rollout.

- [ ] **Step 5: Commit**

```bash
git add modules/hardened/tests/account_baseline.tftest.hcl
git commit -m "test(hardened): assert management-plane break-glass flow"
```

---

### Task 8: Full verification

- [ ] **Step 1: Format check**

Run: `tofu fmt -check -recursive`
Expected: no files listed. If files are listed, run `tofu fmt` (pre-commit hook also re-formats).

- [ ] **Step 2: Full test suite**

Run: `cd modules/hardened && tofu test`
Expected: all runs PASS.

- [ ] **Step 3: Validate all roots**

Run:
```bash
cd 01-management-init-role-and-hardening && tofu validate
cd ../pipeline/account-hardening && tofu validate
cd ../modules/identity && tofu validate
cd ../modules/scp && tofu validate
```
Expected: `Success! The configuration is valid.` everywhere.

- [ ] **Step 4: Commit any residual formatting**

```bash
git add -A
git commit -m "chore: format after break-glass changes" || true
```

- [ ] **Step 5: Report rollout note**

State in the final report: after `01-management` applies, `config.json` carries `break_glass_mgmt_role_arn`; re-run the `pipeline/account-hardening` pipeline once so child roles pick up the management trust. Operator must create the mgmt user password + MFA in the console (module creates the user only). SCP exemption content must be sanity-checked in a real `tofu plan` (mock provider cannot render `aws_iam_policy_document`).

## Self-Review Notes

- Spec coverage: user+MFA trust (Task 3), assume-children policy (Task 3 + Task 4), child trust mgmt role (Task 3), narrowed IAM actions (Task 3), alerts both planes (Task 3), SCP exemption list incl. RequireMFA (Task 1 + Task 4), variable removal/addition across hardened + 01 (Tasks 4-5), pipeline pass-through (Task 6), tests (Task 7), rollout note (Task 8).
- Placeholder scan: no TBD/TODO; every code step shows full code.
- Type consistency: variable names match across tasks (`break_glass_exempt_arns`, `break_glass_user_name`, `break_glass_mgmt_role_arn`, `break_glass_target_account_ids`).
- Known mock limitation: `aws_iam_policy_document` cannot be rendered by `mock_provider`; SCP exemption JSON verified manually at rollout.
