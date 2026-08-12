# Design: Deploy aws-hardened to every account via AFT

Date: 2026-08-12
Status: Approved for implementation
Scope: aws-hardened module repo

## Problem

The aws-hardened module must run in every account of an AWS Control Tower
organization, and new Control Tower accounts must be hardened automatically.
Operators also need an inventory: for each account, which SCPs apply and which
module plane runs there.

## Goals

- One-time backfill: harden all existing org accounts.
- Continuous: every new Control Tower account gets hardened automatically.
- Inventory: list account ID, OU, applicable SCPs, and module feature flags.
- Zero module changes: the existing `management_account` flag already splits
  org-level vs account-level resources.

## Non-Goals

- No full AFT scaffold repo (runbook snippets only; consumer wires it up).
- No SSO assignment to every account (module takes a single
  `sso_target_account_id`; all-accounts wrapper documented as out of scope).
- No CfCT / CloudFormation re-implementation of the module.
- No changes to the log bucket policy (owned by the audit module).

## Architecture

### Key AWS constraint

AFT runs account customizations in each target account, but its
"global customizations" run in the **AFT management account**, which is a
separate account from the Control Tower management account and has no
org-level permissions. Therefore AFT cannot host the management plane.

### Two planes

1. **Management plane** — standalone OpenTofu root in the org management
   account, runs this module with `management_account = true`:
   - five SCPs attached to `ephp_ou_ids`
   - SSO permission sets + group assignments (calling account by default)
   - org CloudTrail + Object Lock log bucket
   - Config delegated admin
   - GuardDuty / Inspector2 / Macie org enablement + delegated admins
   Idempotent; re-run manually or on a schedule.
2. **Account plane** — AFT `account-customizations/` root, runs this module
   with `management_account = false`:
   - IAM password policy, break-glass role
   - per-account Config recorder + rules
   - EBS/S3 encryption defaults
   - GuardDuty / SecurityHub / Inspector2 / Macie per-account resources
   Auto-applied to every new Control Tower account; backfilled to existing
   accounts via AFT account-request files.

### Cross-plane handoff

Management plane creates a small dedicated config bucket and writes a single
`config.json`:

```json
{
  "log_bucket_name": "acme-logs-123456789012-ap-southeast-3",
  "log_bucket_arn": "arn:aws:s3:::acme-logs-123456789012-ap-southeast-3",
  "config_delegated_admin_account_id": "111111111111",
  "guardduty_admin_account_id": "111111111111",
  "inspector_admin_account_id": "111111111111",
  "macie_admin_account_id": "111111111111"
}
```

Bucket policy allows `s3:GetObject` for every org account
(`data "aws_organizations_organization"`). Deliberately separate from the log
bucket: the audit module owns the log bucket policy; this keeps the handoff
independent and makes no module changes. Account customization reads it via
`data "aws_s3_object"`.

## Inventory tool

`scripts/account-inventory.sh` — Bash + `aws` CLI + `jq`, no new dependencies.

Modes:

- `--inventory` (default): full matrix as CSV:
  `account_id, account_name, email, status, ou_id, ou_path, is_management, scps, features`
- `--json`: same data machine-readable, for the deploy tooling.
- `--aft-requests`: emits AFT account-request YAML files for existing accounts
  so one AFT pipeline run backfills all of them.

SCP mapping is accurate per account: resolve the account's OU via
`aws organizations list-parents`, walk ancestors to the root, collect
`aws organizations list-policies-for-target --type SCP` at each level (SCPs
inherit down the OU tree).

Feature column derives from org facts: `management_account=true` for the
management account, otherwise `false`; per-account family flags come from the
defaults (all `true`) — overrides are the operator's responsibility.

## New-account flow

Control Tower Account Factory request -> AFT pipeline -> account
customizations run the module in the new account automatically. No manual
step.

## Versioning and compatibility

- AFT must run Terraform `>= 1.8.0` (module `required_version`,
  `versions.tf`); verify the AFT version supports it before wiring.
- Provider `hashicorp/aws` pinned at `6.58.0` (`versions.tf`).
- AFT customization calls the module via
  `git::https://github.com/example/aws-hardened.git?ref=v1.0.0`.

## Verification

- Existing `tofu test` suite must stay green (no module changes).
- Management plane: `tofu plan` then apply; confirm SCPs appear for target OUs
  via the inventory CSV.
- Account plane: AFT pipeline run completes per account; spot-check one member
  account's resources and re-run `--inventory` to confirm the matrix.
- Object Lock `COMPLIANCE` (default 6 years) on the log bucket: objects are
  immutable; bucket undeletable until retention expires — documented in
  README already.

## Deliverables in this repo

- `docs/aft-deployment.md` — runbook: AFT bootstrap, customization wiring
  (both roots), TF version note, backfill, verification.
- `scripts/account-inventory.sh` — inventory + AFT request generation.
- This design spec.

## Out of scope (documented, not built)

- AFT scaffold repo (consumer creates it from runbook snippets).
- All-accounts SSO assignment wrapper.
- CfCT path.
