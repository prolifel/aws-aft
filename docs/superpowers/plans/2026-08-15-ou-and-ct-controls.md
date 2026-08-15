# OU Creation + Control Tower Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `modules/ou/` (lookup-or-create OUs from `ou_names`) and `modules/ct-controls/` (enable Control Tower managed controls per OU), replacing the `ephp_ou_ids` input with `ou_names` as the single source of truth.

**Architecture:** New org-plane submodules composed by `modules/hardened/`. `modules/ou/` resolves names to IDs (`ou_ids` list for SCP attachment, `ou_map` name→ID for controls). `modules/ct-controls/` enables `aws_controltower_control` per (control × OU) with a per-OU override map and baseline fallback. Both self-skip when `management_account = false`, matching the `scp` family.

**Tech Stack:** OpenTofu >= 1.8.0, AWS provider 6.58.0 (pinned), HCL, `tofu test` with `mock_provider "aws"`.

Spec: `docs/superpowers/specs/2026-08-15-ou-and-ct-controls-design.md`

---

### Task 1: Create `modules/ou/`

**Files:**
- Create: `modules/ou/main.tf`
- Create: `modules/ou/variables.tf`
- Create: `modules/ou/outputs.tf`

- [ ] **Step 1: Create `modules/ou/variables.tf`**

```hcl
variable "enabled" {
  description = "Whether to manage organization units."
  type        = bool
  default     = true
}

variable "management_account" {
  description = "Whether this module runs in the organization management account."
  type        = bool
}

variable "ou_names" {
  description = "OU names to create under the root, or reuse if they already exist."
  type        = list(string)
  nullable    = false
}
```

- [ ] **Step 2: Create `modules/ou/main.tf`**

```hcl
data "aws_organizations_organization" "org" {
  count = var.enabled && var.management_account ? 1 : 0
}

data "aws_organizations_organizational_units" "root" {
  count     = var.enabled && var.management_account ? 1 : 0
  parent_id = data.aws_organizations_organization.org[0].roots[0].id
}

locals {
  existing_ou_ids = var.enabled && var.management_account ? {
    for ou in data.aws_organizations_organizational_units.root[0].children : ou.name => ou.id
  } : {}

  missing_ou_names = toset([
    for name in distinct(var.ou_names) : name
    if !contains(keys(local.existing_ou_ids), name)
  ])
}

resource "aws_organizations_organizational_unit" "this" {
  for_each = var.enabled && var.management_account ? local.missing_ou_names : toset([])

  name      = each.key
  parent_id = data.aws_organizations_organization.org[0].roots[0].id
}
```

- [ ] **Step 3: Create `modules/ou/outputs.tf`**

```hcl
output "ou_ids" {
  description = "OU IDs ordered like ou_names (deduplicated)."
  value = var.enabled && var.management_account ? [
    for name in distinct(var.ou_names) :
    contains(keys(local.existing_ou_ids), name) ? local.existing_ou_ids[name] : aws_organizations_organizational_unit.this[name].id
  ] : []
}

output "ou_map" {
  description = "Map of OU name to OU ID."
  value = var.enabled && var.management_account ? {
    for name in distinct(var.ou_names) :
    name => contains(keys(local.existing_ou_ids), name) ? local.existing_ou_ids[name] : aws_organizations_organizational_unit.this[name].id
  } : {}
}
```

- [ ] **Step 4: Verify syntax**

Run from repo root: `tofu -chdir=modules/hardened validate` (module compiles once wired; run `tofu -chdir=modules/hardened init` first if providers missing).
Expected: exits 0. Pre-commit hook handles `tofu fmt` — do not run formatters manually.

- [ ] **Step 5: Commit**

```bash
git add modules/ou
git commit -m "feat: add OU module (lookup-or-create under root)"
```

---

### Task 2: Create `modules/ct-controls/`

**Files:**
- Create: `modules/ct-controls/main.tf`
- Create: `modules/ct-controls/variables.tf`
- Create: `modules/ct-controls/outputs.tf`

- [ ] **Step 1: Create `modules/ct-controls/variables.tf`**

```hcl
variable "enabled" {
  description = "Whether to enable Control Tower managed controls."
  type        = bool
  default     = true
}

variable "management_account" {
  description = "Whether this module runs in the organization management account."
  type        = bool
}

variable "region" {
  description = "AWS region for the Control Tower control ARNs."
  type        = string
}

variable "ou_map" {
  description = "Map of OU name to OU ID."
  type        = map(string)
  nullable    = false
}

variable "control_map" {
  description = "Per-OU Control Tower control IDs. OUs not listed fall back to baseline."
  type        = map(list(string))
  default     = {}
}

variable "baseline" {
  description = "Default Control Tower control IDs applied to OUs not in control_map."
  type        = list(string)
  nullable    = false
}

variable "excluded_accounts" {
  description = "Account IDs excluded from the OU-scoped controls."
  type        = list(string)
  default     = []
}
```

- [ ] **Step 2: Create `modules/ct-controls/main.tf`**

```hcl
locals {
  ou_controls = {
    for ou_name, ou_id in var.ou_map :
    ou_name => contains(keys(var.control_map), ou_name) ? var.control_map[ou_name] : var.baseline
  }

  ou_control_targets = merge([
    for ou_name, controls in local.ou_controls : {
      for control_id in controls : "${ou_name}/${control_id}" => {
        ou_id      = var.ou_map[ou_name]
        control_id = control_id
      }
    }
  ]...)
}

resource "aws_controltower_control" "this" {
  for_each = var.enabled && var.management_account ? local.ou_control_targets : {}

  control_identifier = "arn:aws:controltower:${var.region}::control/${each.value.control_id}"
  target_identifier  = each.value.ou_id
  excluded_accounts  = length(var.excluded_accounts) > 0 ? var.excluded_accounts : null
}
```

- [ ] **Step 3: Create `modules/ct-controls/outputs.tf`**

```hcl
output "control_ids" {
  description = "IDs of enabled Control Tower controls."
  value       = values(aws_controltower_control.this)[*].id
}
```

- [ ] **Step 4: Verify syntax**

Run: `tofu -chdir=modules/hardened validate`
Expected: exits 0.

- [ ] **Step 5: Commit**

```bash
git add modules/ct-controls
git commit -m "feat: add Control Tower controls module (per-OU map + baseline)"
```

---

### Task 3: Wire into `modules/hardened/` and update tests

**Files:**
- Modify: `modules/hardened/variables.tf` (replace `ephp_ou_ids` block at line 202, add 6 variables)
- Modify: `modules/hardened/main.tf` (scp block line 27-35, add `module "ou"` + `module "ct_controls"`)
- Modify: `modules/hardened/outputs.tf` (add 3 outputs)
- Modify: `modules/scp/variables.tf:17` (rename `ephp_ou_ids` → `ou_ids`)
- Modify: `modules/scp/main.tf:127` (`var.ephp_ou_ids` → `var.ou_ids`)
- Test: `modules/hardened/tests/account_baseline.tftest.hcl`

- [ ] **Step 1: Rename `ephp_ou_ids` in `modules/scp/`**

In `modules/scp/variables.tf`, replace the variable name and description:

```hcl
variable "ou_ids" {
  description = "OU IDs to attach the SCPs to."
  type        = list(string)
  default     = []
}
```

In `modules/scp/main.tf:127`, replace `for ou in var.ephp_ou_ids :` with `for ou in var.ou_ids :`.

- [ ] **Step 2: Replace `ephp_ou_ids` variable in `modules/hardened/variables.tf`**

Delete the `ephp_ou_ids` block (line 202). Add:

```hcl
variable "ou_enabled" {
  description = "Whether to create (or reuse) organization units."
  type        = bool
  default     = true
}

variable "ou_names" {
  description = "OU names to create under the root, or reuse if they already exist."
  type        = list(string)
  default     = []
}

variable "ct_controls_enabled" {
  description = "Whether to enable Control Tower managed controls."
  type        = bool
  default     = true
}

variable "ct_controls_map" {
  description = "Per-OU Control Tower control IDs. OUs not listed fall back to ct_controls_baseline."
  type        = map(list(string))
  default     = {}
}

variable "ct_controls_baseline" {
  description = "Default Control Tower control IDs applied to OUs not in ct_controls_map."
  type        = list(string)
  default = [
    "AWS-GR_S3_BUCKET_PUBLIC_READ_PROHIBITED",
    "AWS-GR_S3_BUCKET_PUBLIC_WRITE_PROHIBITED",
    "AWS-GR_S3_BUCKET_SSL_REQUESTS_ONLY",
    "AWS-GR_S3_VERSIONING_ENABLED",
    "AWS-GR_RDS_SNAPSHOT_PUBLIC_PROHIBITED",
    "AWS-GR_EBS_ENCRYPTION_AT_REST",
    "AWS-GR_KMS_CMK_ROTATION_ENABLED",
    "AWS-GR_LAMBDA_FUNCTION_PUBLIC_PROHIBITED",
    "AWS-GR_ROOT_ACCOUNT_MFA_ENABLED",
    "AWS-GR_ROOT_ACCOUNT_ACCESS_KEY",
    "AWS-GR_ENCRYPTED_VOLUMES",
    "AWS-GR_CLOUDTRAIL_ENABLED",
  ]
}

variable "ct_controls_excluded_accounts" {
  description = "Account IDs excluded from the OU-scoped Control Tower controls."
  type        = list(string)
  default     = []
}
```

- [ ] **Step 3: Update `modules/hardened/main.tf`**

Replace the `module "scp"` block (lines 27-35) with:

```hcl
module "ou" {
  source = "../ou"

  enabled            = var.ou_enabled
  management_account = var.management_account
  ou_names           = var.ou_names
}

module "scp" {
  source = "../scp"

  enabled              = var.scp_enabled
  management_account   = var.management_account
  name_prefix          = var.name_prefix
  ou_ids               = module.ou.ou_ids
  break_glass_role_arn = var.break_glass_role_arn
}

module "ct_controls" {
  source = "../ct-controls"

  enabled            = var.ct_controls_enabled
  management_account = var.management_account
  region             = var.region
  ou_map             = module.ou.ou_map
  control_map        = var.ct_controls_map
  baseline           = var.ct_controls_baseline
  excluded_accounts  = var.ct_controls_excluded_accounts
}
```

- [ ] **Step 4: Add outputs to `modules/hardened/outputs.tf`**

Append:

```hcl
output "ou_ids" {
  description = "IDs of managed OUs."
  value       = module.ou.ou_ids
}

output "ou_map" {
  description = "Map of OU name to OU ID."
  value       = module.ou.ou_map
}

output "ct_control_ids" {
  description = "IDs of enabled Control Tower controls."
  value       = module.ct_controls.control_ids
}
```

- [ ] **Step 5: Update `modules/hardened/tests/account_baseline.tftest.hcl`**

Add mock data for the OU lookups inside the existing `mock_provider "aws"` block (after the `aws_iam_policy_document` mock_data block):

```hcl
  mock_data "aws_organizations_organization" {
    defaults = {
      roots = [{ id = "r-test", name = "Root", arn = "arn:aws:organizations::123456789012:root/o-test/r-test" }]
    }
  }

  mock_data "aws_organizations_organizational_units" {
    defaults = {
      children = [{ id = "ou-existing-1", name = "Sandbox", arn = "arn:aws:organizations::123456789012:ou/o-test/ou-existing-1" }]
    }
  }

  override_resource {
    target = module.ou.aws_organizations_organizational_unit.this["Workloads"]
    values = {
      id = "ou-new-1"
    }
  }
```

In the `management_plane` run, replace `ephp_ou_ids = ["ou-test-1"]` with:

```hcl
    ou_names = ["Sandbox", "Workloads"]
```

Add assertions to `management_plane`:

```hcl
  assert {
    condition     = output.ou_ids == ["ou-existing-1", "ou-new-1"]
    error_message = "management plane must resolve existing and create missing OUs"
  }
  assert {
    condition     = length(output.ct_control_ids) == 24
    error_message = "management plane must enable 12 baseline controls on 2 OUs"
  }
```

In the `ci_management_plane` run, replace `ephp_ou_ids = ["ou-test-1"]` with the same `ou_names` line.

In the `account_plane` run, add assertions:

```hcl
  assert {
    condition     = length(output.ou_ids) == 0
    error_message = "account plane must not manage OUs"
  }
  assert {
    condition     = length(output.ct_control_ids) == 0
    error_message = "account plane must not enable Control Tower controls"
  }
```

- [ ] **Step 6: Run tests**

Run: `cd modules/hardened && tofu test`
Expected: all 3 runs PASS — `management_plane` (5 SCPs, 2 OUs, 24 controls, SSO, CloudTrail, log bucket), `account_plane` (no org-plane resources), `ci_management_plane`.

- [ ] **Step 7: Commit**

```bash
git add modules/hardened modules/scp
git commit -m "feat: wire OU and Control Tower controls into hardened module"
```

---

### Task 4: Update deployment root and example

**Files:**
- Modify: `01-management-init-role-and-hardening/variables.tf` (replace `ephp_ou_ids` at line 31)
- Modify: `01-management-init-role-and-hardening/main.tf:12`
- Modify: `examples/basic/main.tf:23`

- [ ] **Step 1: Replace `ephp_ou_ids` in `01-management-init-role-and-hardening/variables.tf`**

Delete the `ephp_ou_ids` block. Add:

```hcl
variable "ou_names" {
  description = "OU names to create (or reuse) under the root."
  type        = list(string)
  nullable    = false
}

variable "ct_controls_enabled" {
  description = "Whether to enable Control Tower managed controls."
  type        = bool
  default     = true
}

variable "ct_controls_map" {
  description = "Per-OU Control Tower control IDs. OUs not listed fall back to ct_controls_baseline."
  type        = map(list(string))
  default     = {}
}

variable "ct_controls_baseline" {
  description = "Default Control Tower control IDs applied to OUs not in ct_controls_map."
  type        = list(string)
  default = [
    "AWS-GR_S3_BUCKET_PUBLIC_READ_PROHIBITED",
    "AWS-GR_S3_BUCKET_PUBLIC_WRITE_PROHIBITED",
    "AWS-GR_S3_BUCKET_SSL_REQUESTS_ONLY",
    "AWS-GR_S3_VERSIONING_ENABLED",
    "AWS-GR_RDS_SNAPSHOT_PUBLIC_PROHIBITED",
    "AWS-GR_EBS_ENCRYPTION_AT_REST",
    "AWS-GR_KMS_CMK_ROTATION_ENABLED",
    "AWS-GR_LAMBDA_FUNCTION_PUBLIC_PROHIBITED",
    "AWS-GR_ROOT_ACCOUNT_MFA_ENABLED",
    "AWS-GR_ROOT_ACCOUNT_ACCESS_KEY",
    "AWS-GR_ENCRYPTED_VOLUMES",
    "AWS-GR_CLOUDTRAIL_ENABLED",
  ]
}

variable "ct_controls_excluded_accounts" {
  description = "Account IDs excluded from the OU-scoped Control Tower controls."
  type        = list(string)
  default     = []
}
```

- [ ] **Step 2: Update `01-management-init-role-and-hardening/main.tf`**

In the `module "hardened"` block, replace:

```hcl
  ephp_ou_ids                       = var.ephp_ou_ids
```

with:

```hcl
  ou_names                          = var.ou_names
  ct_controls_enabled               = var.ct_controls_enabled
  ct_controls_map                   = var.ct_controls_map
  ct_controls_baseline              = var.ct_controls_baseline
  ct_controls_excluded_accounts     = var.ct_controls_excluded_accounts
```

- [ ] **Step 3: Update `examples/basic/main.tf`**

Replace `ephp_ou_ids = ["ou-EXAMPLE"]` with:

```hcl
  ou_names = ["Sandbox"]
```

- [ ] **Step 4: Verify**

Run: `tofu -chdir=modules/hardened validate`
Expected: exits 0.

- [ ] **Step 5: Commit**

```bash
git add 01-management-init-role-and-hardening examples/basic
git commit -m "feat: expose ou_names and CT control inputs at deployment root"
```

---

### Task 5: README, final verification

**Files:**
- Modify: `README.md` (line 11 scp bullet, line 49-53 Control Tower notes, Usage section)

- [ ] **Step 1: Update README module list**

Replace the `scp` bullet (line 11) with:

```markdown
- **ou** — creates (or reuses) OUs under the root from `ou_names` (management)
- **scp** — five SCPs attached to the managed OUs (management): deny IAM user creation, require MFA, deny unencrypted S3/EBS/RDS, deny public admin ports, deny inline user policies
- **ct-controls** — enables Control Tower managed controls per OU from `ct_controls_map` with a `ct_controls_baseline` fallback (management)
```

- [ ] **Step 2: Update Control Tower notes in README**

After the "SCPs are additive" bullet (line 51), add:

```markdown
- OUs listed in `ou_names` are created if missing; existing names are reused.
  Controls apply once the OU is registered with Control Tower — if apply
  fails with a registration error, register the OU in the console and re-run.
- Removing a control ID from `ct_controls_map`/`ct_controls_baseline` removes
  the resource but does NOT disable the control in AWS — disable it in the
  Control Tower console.
```

- [ ] **Step 3: Update README Usage example**

In the Usage snippet, add `ou_names` and note the breaking change:

```hcl
  ou_names = ["Sandbox"]
```

Add after the snippet:

```markdown
> **Breaking change:** `ephp_ou_ids` is removed; use `ou_names` instead. OUs
> are created or reused automatically and SCPs attach to them.
```

- [ ] **Step 4: Final verification**

Run:
```bash
cd modules/hardened && tofu test
cd ../.. && tofu -chdir=modules/hardened validate
```
Expected: `tofu test` 3 runs PASS; `tofu validate` exits 0. Pre-commit hook checks formatting on commit.

- [ ] **Step 5: Commit**

```bash
git add README.md
git commit -m "docs: document OU and Control Tower controls usage"
```

---

## Self-Review Notes

- Spec items → tasks: OU lookup-or-create (Task 1), per-OU map + baseline fallback (Task 2), `ou_map` name→ID wiring (Task 3), SCP re-targeting to `module.ou.ou_ids` (Task 3), `ephp_ou_ids` removal everywhere including root + example + tests (Tasks 3-4), README breaking-change callout (Task 5), `tofu test` coverage (Task 3 Step 6).
- Baseline control IDs match the spec's curated list exactly (12 entries).
- No placeholders; every code change is shown in full.
- The only spec superset: hardened exposes `ct_controls_map` passthrough so per-OU overrides are settable from the deployment root (the spec's wiring section listed the other three `ct_*` vars; the map is required for the approved Q4-B per-OU behavior).
