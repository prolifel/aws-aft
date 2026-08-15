# Design: OU creation + Control Tower managed controls

Date: 2026-08-15
Status: Approved for implementation
Scope: aws-hardened module repo

## Problem

The module attaches SCPs and security controls to OUs listed in
`ephp_ou_ids`, but cannot create those OUs, and does not enable any
Control Tower managed controls (`aws_controltower_control`). Operators must
create/enroll OUs out-of-band, and the only "controls" available are the
five custom SCPs in `modules/scp/`.

## Decision

Add two organization-plane families:

1. `modules/ou/` — create (or reuse) OUs under the root from a flat
   `ou_names` list. Lookup-or-create: name exists → reuse its ID; missing →
   create. Single source of truth for every OU the module governs.
2. `modules/ct-controls/` — enable Control Tower managed controls per OU via
   `aws_controltower_control`. Per-OU map `control_map` (OU name → control
   IDs) with a curated `baseline` fallback for OUs not listed.

`ephp_ou_ids` is removed. `ou_names` becomes the single user-facing input:
`modules/ou/` produces `ou_ids`, which feeds `modules/scp/` (replacing
`ephp_ou_ids`) and `modules/ct-controls/`. This is a breaking variable
change.

## Goals

- Create OUs from a flat name list; never fail because an OU already exists.
- Enable both preventive and detective Control Tower controls on any
  governed OU with an editable control list.
- Follow repo conventions: per-family module, `*_enabled` flag,
  `management_account = false` self-skip, `.tftest.hcl` coverage.

## Non-Goals

- No nested OU structure (flat under root only).
- No per-OU SSO assignment, no landing-zone configuration
  (`aws_controltower_landing_zone` unchanged).
- No automatic disabling of controls removed from the map — CT controls stay
  enabled in AWS until disabled in the console.
- No OU registration in Control Tower beyond what AWS does automatically.

## Architecture

### modules/ou/

- `variable "enabled"` (bool, default `true`), `variable "management_account"`
  (bool), `variable "ou_names"` (list(string), nullable = false).
- `data "aws_organizations_organizational_units" "root"` (root from
  `data aws_organizations_organization`) — lookup by name.
- `aws_organizations_organizational_unit` with `for_each` over names missing
  from the lookup; existing names resolve to `data...ou_ids[name]`.
- Output `ou_ids`: ordered like `ou_names`, deduplicated (feeds `modules/scp/`).
- Output `ou_map`: map(OU name → OU ID) (feeds `modules/ct-controls/`).
- Self-skips when `management_account = false` (no org-plane actions).

### modules/ct-controls/

- `variable "enabled"` (bool, default `true`), `variable "management_account"`
  (bool), `variable "region"` (string), `variable "ou_map"`
  (map(string → string), OU name → ID), `variable "control_map"`
  (map(string → list(string)), default `{}`), `variable "baseline"`
  (list(string)), `variable "excluded_accounts"` (list(string), default
  `[]`).
- Controls per OU: `control_map[ou_name]` if present, else `baseline`; OU
  IDs resolved from `ou_map`. One `aws_controltower_control` per
  (control × OU):
  `control_identifier = "arn:aws:controltower:${var.region}::control/${id}"`,
  `target_identifier = ou_id`, optional `excluded_accounts` (OU-scoped
  only).
- Self-skips when `management_account = false`.
- Output `control_ids`: flat list of created control resource IDs.

### Baseline controls (curated, editable)

Preventive and detective controls that complement the existing SCPs without
duplicating them (MFA, IAM user creation, encrypted EBS/RDS/S3, admin ports
already denied by `modules/scp/`):

- `AWS-GR_S3_BUCKET_PUBLIC_READ_PROHIBITED`
- `AWS-GR_S3_BUCKET_PUBLIC_WRITE_PROHIBITED`
- `AWS-GR_S3_BUCKET_SSL_REQUESTS_ONLY`
- `AWS-GR_S3_VERSIONING_ENABLED`
- `AWS-GR_RDS_SNAPSHOT_PUBLIC_PROHIBITED`
- `AWS-GR_EBS_ENCRYPTION_AT_REST`
- `AWS-GR_KMS_CMK_ROTATION_ENABLED`
- `AWS-GR_LAMBDA_FUNCTION_PUBLIC_PROHIBITED`
- `AWS-GR_ROOT_ACCOUNT_MFA_ENABLED`
- `AWS-GR_ROOT_ACCOUNT_ACCESS_KEY`
- `AWS-GR_ENCRYPTED_VOLUMES` (detective)
- `AWS-GR_CLOUDTRAIL_ENABLED` (detective)

Operators edit `baseline` or `control_map` freely; invalid IDs fail at
apply time with a clear AWS error.

### modules/hardened/ wiring

- `module "ou"` with `ou_enabled`, `ou_names`.
- `module "scp"`: `ephp_ou_ids` variable removed; receives
  `module.ou.ou_ids`.
- `module "ct_controls"` with `ct_controls_enabled`, `ou_map =
  module.ou.ou_map`, `control_map`, `baseline`, `excluded_accounts`,
  `region` (already a hardened-module input).
- New variables on `modules/hardened/`: `ou_enabled`, `ou_names`,
  `ct_controls_enabled`, `ct_controls_baseline`, `ct_controls_excluded_accounts`.
- Root `01-management-init-role-and-hardening/` passes `ou_names`; its
  `ephp_ou_ids` variable is removed.

## Decisions

- **Flat OUs under root** (option A) over nested — repo has no topology
  inputs today; nesting is a later extension of `modules/ou/`.
- **`ou_names` single source** (option B) over keeping `child_ou_ids` —
  module-derived IDs guarantee SCP and CT-control targets match created OUs.
- **Lookup-or-create** (option A) over fail-hard — orgs already have legacy
  OUs; creation must not block on pre-existing names.
- **Control Tower managed controls** over more custom SCPs — user's explicit
  choice; SCPs stay additive and `aws-guardrails-*` untouched.
- **Uniform baseline + per-OU override map** (Q4-B, Q5-B) — empty map means
  baseline everywhere; listing an OU overrides for that OU only.
- **Editable control IDs** — baseline is a default list, not a hardcoded
  contract; operators add/remove IDs without code changes.

## Operational notes

- OUs created via Organizations API may need Control Tower registration
  before `aws_controltower_control` accepts them. If apply fails with a
  registration error, register the OU once in the CT console, then re-run.
- Removing a control ID from `control_map`/`baseline` removes the Terraform
  resource but does NOT disable the control in AWS — disable manually in the
  CT console. Documented as a known behavior, not a bug.
- Preventive (SCP-backed) controls take effect in minutes; detective
  (Config-backed) controls report within ~1 hour.
- `aws_controltower_control` is idempotent; re-running apply reconciles
  changed `control_map`/`baseline` entries.

## Verification

- `tofu fmt` — format-clean diff.
- `tofu validate` — compiles from `modules/hardened/`.
- `tofu test` — new `.tftest.hcl` run blocks assert `aws_organizations_organizational_unit`
  and `aws_controltower_control` resources appear in plan with
  `mock_provider "aws" {}`; existing SCP tests still pass with `ou_ids` from
  the OU module.
- Breaking-change callout: `ephp_ou_ids` removed from variables/outputs;
  README and root variables updated.

## Files touched

- `modules/ou/` (new): `main.tf`, `variables.tf`, `outputs.tf`
- `modules/ct-controls/` (new): `main.tf`, `variables.tf`, `outputs.tf`
- `modules/hardened/`: `main.tf`, `variables.tf`
- `modules/scp/`: `variables.tf` (rename `ephp_ou_ids` → `ou_ids`), `main.tf`
- `01-management-init-role-and-hardening/`: `main.tf`, `variables.tf`
- `modules/hardened/tests/`: new `.tftest.hcl`
- `README.md`: OU + control usage, breaking-change note
