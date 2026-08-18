# Design: Management-plane break-glass with child-account assume

Date: 2026-08-19
Status: Approved for implementation
Scope: aws-hardened module repo

## Problem

Break-glass access today is per-account and unusable end-to-end. Each member
account gets a `break-glass` role (`modules/identity/main.tf:93`) with a
deny-by-default (empty) trust policy and a narrow read-only inline policy,
plus SNS/EventBridge alerts on assume. The management account gets no
break-glass surface at all, and the SCP exemption is a single caller-supplied
`break_glass_role_arn` string that can exempt only one role.

The goal: emergency credentials live in the management account. An operator
logs in as a designated IAM user (MFA), assumes a management-account
break-glass role, then assumes into a dedicated role in every child account to
perform narrow recovery actions — including creating an IAM user with a policy
attached, so the operator can hand usable access to a responder.

## Decision

1. **Management plane (`01-management-init-role-and-hardening`,
   `management_account = true`):**
   - `modules/identity/` creates a designated IAM user
     (`break_glass_user_name`, default `break-glass-user`). No access keys;
     operator sets password and enrolls MFA out-of-band.
   - `modules/identity/` now creates the `break-glass` role in the management
     account too (currently skipped — `modules/identity/main.tf:93` gates on
     `!management_account`). Trust policy: only the designated user, with
     `aws:MultiFactorAuthPresent = true`.
   - Mgmt-account role inline policy: existing read-only actions plus
     `sts:AssumeRole` on every child `break-glass` role, auto-derived from
     `aws_organizations_organization.accounts` (excluding the management
     account). New child accounts are covered without variable changes.
   - SNS + EventBridge assume-alert for the mgmt-account role, mirroring the
     existing child pattern (`modules/identity/main.tf:137`).
2. **Child accounts (`pipeline/account-hardening`, `management_account =
   false`):**
   - Repurpose the existing per-account `break-glass` role: trust policy
     changes from deny-all to "management-account `break-glass` role only"
     (input `break_glass_mgmt_role_arn`).
   - Inline policy: existing read-only actions plus `iam:CreateUser`,
     `iam:CreateLoginProfile`, `iam:AttachUserPolicy`. No
     `iam:CreateAccessKey` — console login only.
   - Existing SNS/EventBridge assume-alerts remain unchanged.
3. **SCP module (`modules/scp/`):**
   - `break_glass_role_arn` variable removed. Exemption list derived
     internally: all member-account `break-glass` role ARNs (org-derived) plus
     the management-account role ARN.
   - Exempted from all three denials that would otherwise block the flow:
     `DenyIAMUserCreations` (`iam:CreateUser`, `iam:CreateAccessKey`),
     `DenyIAMUserInlinePolicies` (`iam:PutUserPolicy`, `iam:AttachUserPolicy`,
     `iam:CreateUser`), and `RequireMFA` — role chaining does not carry MFA
     context, so child roles must be exempt from the MFA denial.

## Goals

- Emergency access works in one flow: mgmt IAM user (MFA) → mgmt
  `break-glass` role → child `break-glass` role → create user with attached
  policy.
- No caller-supplied role ARN list: SCP exemptions and assume targets are
  derived from the org, and track accounts added later.
- Alerts fire on both hops (mgmt role assume, child role assume).
- Child accounts keep a single break-glass role — no duplication.

## Non-Goals

- No `iam:CreateAccessKey` anywhere in the break-glass flow (console-only
  users).
- No root-user-based access path.
- No per-OU variation in the child role policy (all child accounts identical).
- No rotation of the mgmt IAM user's credentials or MFA (operator-managed,
  out-of-band).

## Architecture

### modules/identity/

- `variable "break_glass_user_name"` (string, default `break-glass-user`).
- `variable "break_glass_mgmt_role_arn"` (string, default `""`) — used by the
  child-plane trust policy; empty disables child-plane break-glass creation.
- `variable "break_glass_target_account_ids"` (list(string)) — org-derived
  child account IDs passed from the mgmt plane; empty on child plane.
- Break-glass role now created in both planes:
  - Mgmt plane: trust = designated user + MFA; inline policy = read-only +
    `sts:AssumeRole` over `break_glass_target_account_ids` →
    `arn:aws:iam::<id>:role/<break_glass_role_name>`.
  - Child plane: trust = `break_glass_mgmt_role_arn`; inline policy =
    read-only + `iam:CreateUser` / `iam:CreateLoginProfile` /
    `iam:AttachUserPolicy`.
- `aws_iam_user` only; operator sets password and enrolls MFA in the
  console, out-of-band.
- Mgmt-plane SNS + `aws_cloudwatch_event_rule` on mgmt role `AssumeRole`.
- Outputs: `break_glass_role_arn` (existing) now also populated on the mgmt
  plane; new output `break_glass_user_name`.

### modules/scp/

- `variable "break_glass_role_arn"` removed.
- `variable "break_glass_exempt_arns"` (list(string)) — mgmt-plane derived:
  member `break-glass` ARNs from `aws_organizations_organization.accounts`
  plus the mgmt role ARN. Replaces the single-ARN dynamic condition in
  `deny_iam_user_creations`, `deny_iam_user_inline_policies`, and
  `require_mfa` with `ArnNotEquals` over the list.

### modules/hardened/ + 01-management-init-role-and-hardening/

- Remove `break_glass_role_arn` from both `variables.tf` files.
- Add `break_glass_user_name` pass-through.
- Mgmt plane derives child account IDs (org data source) and the mgmt role
  ARN (org mgmt account ID + `break_glass_role_name`) and feeds them to
  `module.identity` and `module.scp`.
- Per-account pipeline roots pass `break_glass_mgmt_role_arn` (management
  role ARN) into `modules/hardened/`.

## Variable / Output Changes

- Removed: `break_glass_role_arn` (hardened + scp + 01-management).
- Added: `break_glass_user_name` (hardened + identity),
  `break_glass_mgmt_role_arn` (hardened + identity),
  `break_glass_exempt_arns` (scp, internal wiring only).
- Output `break_glass_role_arn` now also populated in the management plane;
  new output `break_glass_user_name`.

## Testing

- `modules/hardened/tests/*.tftest.hcl`: mgmt-plane run asserts `iam_user`
  break-glass resources in plan; child-plane run asserts trust policy change
  and the three IAM actions in the inline policy.
- SCP run asserts `DenyIAMUserCreations` / `DenyIAMUserInlinePolicies` /
  `RequireMFA` documents contain `ArnNotEquals` over the exemption list.
- `tofu fmt`, `tofu validate`, `tofu test` before PR.
