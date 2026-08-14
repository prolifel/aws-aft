# Deploying to every account via GitLab CI/CD

Replaces the AFT runbook. GitLab CI/CD drives the account lifecycle; there is
no AFT, no CodeBuild, and no CodePipeline. See the design spec
`docs/superpowers/specs/2026-08-14-gitlab-native-design.md`.

## Prerequisites

- AWS Control Tower landing zone (Account Factory product in Service Catalog).
- Self-hosted GitLab with the OIDC ingress from `docs/gitlab-oidc/`.
- OpenTofu >= 1.8.0 locally for bootstrap, `aws` CLI, `jq`.

## 1. AWS side: `modules/ci/`

In the org management account, call the module with `ci_enabled = true`:

```hcl
module "hardened" {
  source = "git::https://github.com/example/aws-hardened.git?ref=v1.0.0"

  management_account  = true
  ci_enabled          = true
  gitlab_url          = "https://gitlab.example.com"
  gitlab_project_path = "prolifel/aws-aft"
  config_bucket_arn   = aws_s3_bucket.config.arn
}
```

This creates the GitLab OIDC provider and the `gitlab-ci` role. Record the
role ARN from `output.gitlab_ci_role_arn` for `CI_ROLE_ARN`.

## 2. Deployment repo scaffold

Repurpose the deployment repo (e.g. `prolifel/aws-aft`):

- `.gitlab-ci.yml` and `ci/oidc.sh` — copy from this repo.
- `scripts/` — copy `account-inventory.sh`, `account-factory.sh`,
  `account-plane.sh`.
- `accounts/*.yaml` — one request file per account (see format below).
- `management/` — management-plane root (this module,
  `management_account = true`, plus the handoff config bucket + `config.json`
  object from the old runbook).
- `account-plane/` — account-plane root:

```hcl
terraform {
  backend "s3" {
    bucket         = "<aft-backend-bucket>"
    region         = "ap-southeast-3"
    encrypt        = true
    dynamodb_table = "<lock-table>"
    key            = "placeholder" # real key passed at tofu init
  }
}

data "aws_s3_object" "config" {
  bucket = var.config_bucket_name
  key    = "config.json"
}
```

The `key` is overridden per account at `tofu init` by
`scripts/account-plane.sh` (`${account_id}/account-plane.tfstate`). Use the
same backend bucket + lock table as the AFT backend (or create a new one in
the management-plane root).

- `account-bootstrap/` — bootstrap root that creates the per-account
  `hardened-deploy` role trusting the `gitlab-ci` role:

```hcl
variable "account_id" {}

data "aws_iam_policy_document" "trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [var.gitlab_ci_role_arn] # e.g. from module output
    }
  }
}

resource "aws_iam_role" "hardened_deploy" {
  name               = "hardened-deploy"
  assume_role_policy = data.aws_iam_policy_document.trust.json
}

resource "aws_iam_role_policy_attachment" "admin" {
  role       = aws_iam_role.hardened_deploy.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

Set `CI_ROLE_ARN` and `CONFIG_BUCKET_ARN` as GitLab CI/CD variables.

`hardened-deploy` carries `AdministratorAccess` inside the member account —
the same effective scope AFT's `AWSAFTExecution` had, and required to run the
account-plane module (IAM, Config, GuardDuty, SecurityHub, Inspector2, Macie,
KMS, S3, EC2) and delete default VPCs.

## 3. Request file format

`accounts/<name>.yaml`:

```yaml
account_name: App-A
email: app-a@example.com
managed_org_unit: ePHI-A-Prod
sso_user_email: app-a@example.com
sso_user_first_name: App
sso_user_last_name: A
account_tags:
  Environment: Dev
customizations: aws-hardened
```

`scripts/account-inventory.sh --aft-requests <dir>` generates these files for
all existing member accounts (management account and root-level accounts
skipped with a warning).

## 4. Backfill existing accounts

Generate request files, commit them, and merge. The `provision` job skips
Service Catalog for accounts already in Organizations; the `customize` job
bootstraps `hardened-deploy` and applies the account plane per account.

## 5. New accounts

Add `accounts/*.yaml` in an MR. The `provision` job calls
`ProvisionProduct` (or `UpdateProvisionedProduct` for OU/tag changes), polls
until `AVAILABLE`, then the `customize` job applies the account plane.
Delete the YAML to remove the account; set `ALLOW_TERMINATE=1` as a CI
variable to let `provision` terminate stale provisioned products
(destructive — MR review is the gate).

### Default VPC removal

Optional, matches AFT's `aft_feature_delete_default_vpcs_enabled`: set
`DELETE_DEFAULT_VPCS=1` as a CI/CD variable. The `customize` job then deletes
the default VPC (subnets + internet gateway first) in every enabled region of
each account, before applying the account plane. Only default VPCs
(`isDefault=true`) are touched; regions without one are skipped.

## 6. Drift and inventory

Scheduled pipelines run `management-plane` (daily) and `customize` (all
accounts) and `inventory` (report). Manual runs via the GitLab web UI.

## 7. Remove AFT

1. Run the pipeline once so every account is hardened outside AFT.
2. `tofu destroy` the AFT core in the AFT management account.
3. Delete `aft/` from this repo (already done) and the old runbook.
4. Optional: delete the AFT management account.

## Verify

- `curl` the OIDC discovery endpoints (see `docs/gitlab-oidc/`).
- A scheduled pipeline completes: management-plane apply, customize for every
  account, inventory report.
- `scripts/account-inventory.sh --inventory` shows every account with the
  expected SCPs and `management_account=false`.
- No CodeBuild/CodePipeline resources remain in the AFT management account.
