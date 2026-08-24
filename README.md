# AWS Hardened

OpenTofu module that applies a HIPAA §164.312 security baseline to an AWS
organization built on Control Tower + IAM Identity Center + AWS Organizations.

## Features

Five control families, each behind an `*_enabled` flag:

- **identity** — SSO permission sets + group assignments (management), IAM password policy, break-glass role with deny-by-default trust + SNS alert (account)
- **scp** — five SCPs attached to ePHI OUs (management): deny IAM user creation, require MFA, deny unencrypted S3/EBS/RDS, deny public admin ports, deny inline user policies
- **encryption** — KMS CMK with rotation, EBS default encryption, S3 account public access block
- **detection** — GuardDuty + SecurityHub + Inspector2 + Macie org enablement (management) and per-account detectors/jobs

## Requirements

- OpenTofu `>= 1.8.0` (or Terraform `>= 1.8.0`)
- AWS credentials with permissions for the resources you enable
- Provider `hashicorp/aws` pinned at `6.58.0` (`versions.tf`)

## Deployment

Run the same module in every account. Set `management_account = true` only in the
management account — SCPs, SSO, and org-wide enablement self-skip elsewhere.

### GitLab CI/CD (recommended)

This repo is also the deployment repo: numbered roots run in order, pipelines
do the per-account work. Full runbook: `docs/gitlab-deployment.md`.

| Folder | When | Who runs it |
|---|---|---|
| `00-backend/` | once, first | you, manually — state bucket |
| `01-management-init-role-and-hardening/` | once, second | you, manually — org hardening + `gitlab-ci` role |
| `02-accounts-creation/*.yaml` | every account change | GitLab `provision` job — create/update accounts |
| `pipeline/account-init-role/` | per account, auto | GitLab `customize` job — per-account deploy role |
| `pipeline/account-hardening/` | per account, auto | GitLab `customize` job — hardened config |

Manual steps are just the first two: apply `00-backend`, then
`01-management-init-role-and-hardening` (gives `CI_ROLE_ARN`). After that,
add/edit `02-accounts-creation/*.yaml` and merge — the pipeline creates the account and
hardens it. New accounts get `hardened-deploy` bootstrapped inside them via
Control Tower's `AWSControlTowerExecution`, then the module runs
`management_account = false` with per-account state.

### Manual

Control Tower notes:

- SCPs are additive; never edit Control Tower `aws-guardrails-*` SCPs.
- SecurityHub is already enabled by Control Tower. In managed accounts, run
  `terraform import 'module.detection.aws_securityhub_account.this[0]' <region-arn>` once if apply
  reports the account is already registered.
- CloudTrail and AWS Config are centralized via Control Tower managed controls;
  this module no longer provisions Config rules, remediations, or a log bucket.

## Usage

```hcl
module "hardened" {
  source = "git::https://github.com/prolifel/aws-aft.git//modules/hardened?ref=v1.0.0"

  management_account = false
  name_prefix        = "prod"
  tags               = { Environment = "production" }
}
```

The module lives in `modules/hardened/`; this repo root is the deployment
layout. See `examples/basic` for a complete standalone example.

## Commands

```sh
tofu init       # download providers, generate lock file
tofu validate   # validate configuration syntax
tofu plan       # show changes before applying
tofu apply      # apply the baseline
tofu test       # run smoke test suite (uses mocks, no AWS account needed)
tofu fmt        # format .tf files
```

## Notes

- Break-glass trust policy is deny-by-default (empty statement list); it must be
  flipped out-of-band before use, and every assumption fires an SNS alert.
