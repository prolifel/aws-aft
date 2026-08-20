# Design: Consolidate custom SCPs into one policy

Date: 2026-08-20
Status: Approved for implementation
Scope: aws-hardened module repo

## Problem

`modules/scp/` creates five separate `aws_organizations_policy` resources
(`DenyIAMUserCreations`, `RequireMFA`, `DenyUnencryptedResources`,
`DenyPublicAdminPorts`, `DenyIAMUserInlinePolicies`), each attached to the
same `ephp_ou_ids`. Five policies mean five org-wide attachments and five
names to track; the controls are all management-plane hardening and never
attached independently, so the split has no operational value.

Goal: one custom SCP. All existing denials remain functionally identical,
statements (SIDs) preserved.

## Decision

Use the AWS provider's `source_policy_documents` merge on
`aws_iam_policy_document` — keep the five existing document blocks as-is
(their dynamic break-glass exemption conditions stay intact) and merge their
JSON into one document consumed by a single `aws_organizations_policy`.

1. **`modules/scp/main.tf`:**
   - Keep all five existing `data "aws_iam_policy_document"` blocks unchanged.
   - Add `data "aws_iam_policy_document" "combined"` with
     `source_policy_documents` = the five existing JSON documents.
   - Delete `locals.scp_policies` and `locals.scp_attachments` (no longer
     needed).
   - Replace `aws_organizations_policy.this` (for_each over 5) with a single
     `aws_organizations_policy.hardening`: name `${var.name_prefix}-hardening`,
     description "Consolidated HIPAA 164.312 control SCP", content =
     `data.aws_iam_policy_document.combined.json`, no `Control` tag.
   - `aws_organizations_policy_attachment.this` keeps `for_each` over
     `ephp_ou_ids`; point `policy_id` at the single policy.
2. **`modules/scp/outputs.tf`:** replace list outputs `scp_policy_ids` /
   `scp_policy_names` with single values `scp_policy_id` / `scp_policy_name`.
   Breaking change for consumers.
3. **`modules/hardened/outputs.tf`:** pass through the new single outputs.
4. **`examples/basic/main.tf`:** update the `scp_policy_ids` output block to
   the new output names.
5. **`modules/hardened/tests/account_baseline.tftest.hcl`:** assert `output.scp_policy_id != ""` and `output.scp_policy_name == "${var.name_prefix}-hardening"` (was `length == 5`).

## Goals

- One `aws_organizations_policy` resource, one name, one attachment set.
- All statements, SIDs, and break-glass exemption logic preserved verbatim.
- Tests updated to prove the single-policy shape; `tofu test` and
  `tofu validate` pass.

## Non-goals

- No changes to statement content, conditions, or exemption behavior.
- No changes to which OUs receive the policy.
- No renaming of existing controls beyond the single policy name.

## Verification

- `cd modules/scp && tofu init -backend=false && tofu validate`
- `cd modules/hardened && tofu test`
- `tofu fmt` clean.
