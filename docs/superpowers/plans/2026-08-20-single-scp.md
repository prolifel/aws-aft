# Single Consolidated SCP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the five separate `aws_organizations_policy` resources in `modules/scp/` with one consolidated policy whose document is merged from the five existing `aws_iam_policy_document` blocks.

**Architecture:** Keep the five existing `data "aws_iam_policy_document"` blocks unchanged (they hold the per-control statements and break-glass exemption dynamics). Add a sixth `data "aws_iam_policy_document" "combined"` that uses `source_policy_documents` to merge their JSON. One `aws_organizations_policy.hardening` resource (`count = 0/1` on `local.scp_enabled`) consumes it; the attachment `for_each` stays over `ephp_ou_ids`. Outputs change from lists to single values, and pass through `modules/hardened` to `examples/basic`.

**Tech Stack:** OpenTofu `>= 1.8.0`, AWS provider (exact pin in `versions.tf`). Tests are `.tftest.hcl` with `mock_provider "aws" {}`.

---

### Task 1: Red test — expect exactly one SCP

**Files:**
- Modify: `modules/hardened/tests/account_baseline.tftest.hcl:113-116` (management plane assert)
- Modify: `modules/hardened/tests/account_baseline.tftest.hcl:155-158` (account plane assert)

- [ ] **Step 1: Update the management-plane assert to single SCP shape**

Replace:

```hcl
  assert {
    condition     = length(output.scp_policy_ids) == 5
    error_message = "management plane must create exactly 5 SCPs"
  }
```

with:

```hcl
  assert {
    condition     = output.scp_policy_id != "" && output.scp_policy_name == "test-hardening"
    error_message = "management plane must create exactly one SCP"
  }
```

- [ ] **Step 2: Update the account-plane assert to expect empty single value**

Replace:

```hcl
  assert {
    condition     = length(output.scp_policy_ids) == 0
    error_message = "account plane must not create SCPs"
  }
```

with:

```hcl
  assert {
    condition     = output.scp_policy_id == ""
    error_message = "account plane must not create SCPs"
  }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `cd modules/hardened && tofu test`
Expected: FAIL — `scp_policy_id` output does not exist yet (undefined output reference), proving the test encodes the new contract.

---

### Task 2: Merge documents and create single SCP resource

**Files:**
- Modify: `modules/scp/main.tf:107-144` (locals + resources)
- Modify: `modules/scp/outputs.tf:1-9`

- [ ] **Step 1: Add the combined policy document**

After the `data "aws_iam_policy_document" "deny_iam_user_inline_policies"` block (ends at line 105), insert:

```hcl
data "aws_iam_policy_document" "combined" {
  source_policy_documents = [
    data.aws_iam_policy_document.deny_iam_user_creations.json,
    data.aws_iam_policy_document.require_mfa.json,
    data.aws_iam_policy_document.deny_unencrypted_resources.json,
    data.aws_iam_policy_document.deny_public_admin_ports.json,
    data.aws_iam_policy_document.deny_iam_user_inline_policies.json,
  ]
}
```

- [ ] **Step 2: Delete the two locals blocks**

Delete `locals { scp_policies = { ... } }` (lines 107-113) and `locals { scp_attachments = merge([ ... ]...) }` (lines 115-124). Both become dead — the single policy needs neither the name map nor the policy-id-per-attachment map.

- [ ] **Step 3: Replace the policy resource**

Replace `resource "aws_organizations_policy" "this" { ... }` (lines 126-137) with:

```hcl
resource "aws_organizations_policy" "hardening" {
  count = local.scp_enabled ? 1 : 0

  name        = "${var.name_prefix}-hardening"
  description = "Consolidated HIPAA 164.312 control SCP"
  type        = "SERVICE_CONTROL_POLICY"
  content     = data.aws_iam_policy_document.combined.json
}
```

- [ ] **Step 4: Update the attachment resource**

Replace `resource "aws_organizations_policy_attachment" "this" { ... }` (lines 139-144) with:

```hcl
resource "aws_organizations_policy_attachment" "this" {
  for_each = local.scp_enabled ? { for ou in var.ephp_ou_ids : ou => ou } : {}

  policy_id = aws_organizations_policy.hardening[0].id
  target_id = each.key
}
```

- [ ] **Step 5: Replace outputs with single values**

Replace `modules/scp/outputs.tf` in full with:

```hcl
output "scp_policy_id" {
  description = "ID of the consolidated hardening SCP, empty when disabled."
  value       = local.scp_enabled ? aws_organizations_policy.hardening[0].id : ""
}

output "scp_policy_name" {
  description = "Name of the consolidated hardening SCP, empty when disabled."
  value       = local.scp_enabled ? aws_organizations_policy.hardening[0].name : ""
}
```

- [ ] **Step 6: Validate the module**

Run: `cd modules/scp && tofu init -backend=false && tofu validate`
Expected: PASS — no syntax or reference errors.

- [ ] **Step 7: Commit**

```bash
git add modules/scp/main.tf modules/scp/outputs.tf
git commit -m "refactor(scp): merge five SCPs into one policy"
```

---

### Task 3: Pass through single outputs from hardened

**Files:**
- Modify: `modules/hardened/outputs.tf:46-53`

- [ ] **Step 1: Replace the two list outputs**

Replace:

```hcl
output "scp_policy_ids" {
  description = "IDs of created SCPs."
  value       = module.scp.scp_policy_ids
}

output "scp_policy_names" {
  description = "Names of created SCPs."
  value       = module.scp.scp_policy_names
}
```

with:

```hcl
output "scp_policy_id" {
  description = "ID of the consolidated hardening SCP."
  value       = module.scp.scp_policy_id
}

output "scp_policy_name" {
  description = "Name of the consolidated hardening SCP."
  value       = module.scp.scp_policy_name
}
```

- [ ] **Step 2: Commit**

```bash
git add modules/hardened/outputs.tf
git commit -m "refactor(hardened): pass through single SCP outputs"
```

---

### Task 4: Update standalone example

**Files:**
- Modify: `examples/basic/main.tf:37-39`

- [ ] **Step 1: Replace the example output**

Replace:

```hcl
output "scp_policy_ids" {
  value = module.hardened.scp_policy_ids
}
```

with:

```hcl
output "scp_policy_id" {
  value = module.hardened.scp_policy_id
}
```

- [ ] **Step 2: Commit**

```bash
git add examples/basic/main.tf
git commit -m "chore(examples): use single SCP output"
```

---

### Task 5: Green verification pass

**Files:** none modified (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `cd modules/hardened && tofu test`
Expected: PASS — both runs (`management_plane`, `account_plane`) green.

- [ ] **Step 2: Format check**

Run: `cd modules/hardened && tofu fmt -check ..`
Expected: no unformatted files reported. If any file is listed, run `tofu fmt` on it and commit as `chore: format`.

- [ ] **Step 3: Final commit (only if Step 2 changed files)**

```bash
git add -A
git commit -m "chore: format after scp consolidation"
```

---

## Self-Review Notes

- **Spec coverage:** Decision items 1-5 map to Tasks 2 (module), 3 (hardened outputs), 4 (examples), 1 (tests). Verification goals map to Task 5. Non-goals preserved: no statement content, condition, OU, or variable changes.
- **Type consistency:** `scp_policy_id`/`scp_policy_name` are single strings everywhere (scp module → hardened → example → tests). No list output remains anywhere.
- **Edge cases:** `count = 0` (account plane) guarded in outputs via `local.scp_enabled ? ... : ""`, matching the account-plane test assert. SIDs across the five source documents are unique, so `source_policy_documents` merge is safe.
