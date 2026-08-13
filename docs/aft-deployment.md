# Deploying to every account via AFT

Architecture summary: the module's management plane runs standalone in the org
management account; the account plane runs via AFT account customizations in
every member account. See the design spec
`docs/superpowers/specs/2026-08-12-aft-all-accounts-design.md` for rationale.

## Prerequisites

- AWS Control Tower landing zone (AFT requires it).
- A dedicated AFT management account (a normal org account; it does not need
  org management permissions).
- OpenTofu >= 1.8.0, `aws` CLI, `jq`.

## 1. Bootstrap AFT in the dedicated account

Follow the official AFT getting-started flow (`aws-aft-core`), deployed into
the AFT management account:

- Pick a home region and set the Terraform version to `1.8.x` or newer — the
  module requires `>= 1.8.0` (`versions.tf`).
- After bootstrap, the AFT account customizations repo is created. You commit
  account customizations there; AFT runs them in each target account.

## 2. Management plane (org management account)

Create a root that calls the module with `management_account = true`, plus a
handoff config bucket. Example `main.tf`:

```hcl
data "aws_organizations_organization" "org" {}

data "aws_caller_identity" "current" {}

variable "region" {
  default = "ap-southeast-3"
}

module "hardened" {
  source = "git::https://github.com/example/aws-hardened.git?ref=v1.0.0"

  management_account = true
  name_prefix        = "prod"
  region             = "ap-southeast-3"
  tags               = { Environment = "production" }

  ephp_ou_ids                   = ["ou-aaaa", "ou-bbbb"]  # your ePHI OU IDs (SCP targets)
  break_glass_role_arn          = "arn:aws:iam::111111111111:role/break-glass"
  config_delegated_admin_account_id = "444444444444"
  guardduty_admin_account_id        = "444444444444"
  inspector_admin_account_id        = "444444444444"
  macie_admin_account_id            = "444444444444"
}

resource "aws_s3_bucket" "config" {
  bucket        = "aws-hardened-config-${data.aws_caller_identity.current.account_id}-${var.region}"
  force_destroy = false
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config.json
}

data "aws_iam_policy_document" "config" {
  statement {
    effect = "Allow"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.config.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [for a in data.aws_organizations_organization.org.accounts : "arn:aws:iam::${a.id}:root"]
    }
  }
}

resource "aws_s3_object" "config" {
  bucket  = aws_s3_bucket.config.id
  key     = "config.json"
  content = jsonencode({
    log_bucket_name  = module.hardened.log_bucket_id
    log_bucket_arn   = module.hardened.log_bucket_arn
    config_delegated_admin_account_id = "444444444444"
    guardduty_admin_account_id        = "444444444444"
    inspector_admin_account_id        = "444444444444"
    macie_admin_account_id            = "444444444444"
  })
}
```

Adjust `ephp_ou_ids` (SCP targets), the delegated admin IDs, and the module
`ref`. Run `tofu init && tofu plan && tofu apply`.

## 3. Account customizations (AFT repo)

In the AFT account customizations repo, create the folder
`account-customizations/aws-hardened/terraform/` (the folder name must match
the `account_customizations_name` value used in account requests). Add
`main.tf`:

```hcl
data "aws_s3_object" "config" {
  bucket = "aws-hardened-config-111111111111-ap-southeast-3" # must match the management-plane bucket
  key    = "config.json"
}

locals {
  config = jsondecode(data.aws_s3_object.config.body)
}

module "hardened" {
  source = "git::https://github.com/example/aws-hardened.git?ref=v1.0.0"

  management_account = false
  name_prefix        = "prod"
  region             = "<region>"
  tags               = { Environment = "production" }

  log_bucket_name   = local.config.log_bucket_name
  log_bucket_arn    = local.config.log_bucket_arn
}
```

Commit and push. The AFT pipeline runs this in every account that references
`account_customizations_name: aws-hardened`.

## 4. Backfill existing accounts

```sh
scripts/account-inventory.sh --inventory        # see the full account/OU/SCP matrix
scripts/account-inventory.sh --aft-requests <dir>  # write request files
```

Copy the generated `<account_id>.yaml` files into the AFT repo
`account_request/` directory, commit, and push. AFT runs the account
customizations for each account. Accounts sitting directly at the root are
skipped with a warning — move them into an OU first.

If your AFT version's request schema differs (extra required fields such as
SSO fields), update the generated files accordingly; AFT rejects requests with
invalid fields and reports them via its SNS topic.

## 5. New accounts

Include `account_customizations_name: aws-hardened` in the Account Factory
request. AFT runs the account customizations automatically after provisioning.

## 6. Verify

```sh
scripts/account-inventory.sh --inventory   # confirm every account shows the expected SCPs
bash tests/inventory_test.sh               # local check, no AWS calls
tofu test                                  # module smoke suite unchanged
```

## Operations notes

- The inventory tool is read-only; the `--aft-requests` mode only writes local
  YAML files.
- The log bucket uses Object Lock `COMPLIANCE` (default 6 years): log objects
  are immutable and the bucket cannot be deleted until retention expires.
- SSO permission-set assignment targets a single account
  (`sso_target_account_id`); assigning to every account needs a wrapper around
  the module (out of scope).
- The provider is pinned at `6.58.0` (`versions.tf`); bump deliberately and
  re-run `tofu validate`.
