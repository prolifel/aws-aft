# AWS Hardened

OpenTofu module that applies a HIPAA §164.312 security baseline to an AWS
organization built on Control Tower + IAM Identity Center + AWS Organizations.

## Features

Five control families, each behind an `*_enabled` flag:

- **identity** — SSO permission sets + group assignments (management), IAM password policy, break-glass role with deny-by-default trust + SNS alert (account)
- **scp** — five SCPs attached to ePHI OUs (management): deny IAM user creation, require MFA, deny unencrypted S3/EBS/RDS, deny public admin ports, deny inline user policies
- **audit** — org CloudTrail with log file validation + data event selectors, Object Lock COMPLIANCE log bucket, Config recorder + 12 managed rules + HIPAA conformance pack (account)
- **encryption** — KMS CMK with rotation, EBS default encryption, S3 account public access block
- **detection** — GuardDuty + SecurityHub + Inspector2 + Macie org enablement (management) and per-account detectors/jobs

## Requirements

- OpenTofu `>= 1.8.0` (or Terraform `>= 1.8.0`)
- AWS credentials with permissions for the resources you enable
- Provider `hashicorp/aws` pinned at `6.58.0` (`versions.tf`)

## Deployment

Run the same module in every account. Set `management_account = true` only in the
management account — SCPs, SSO, and org-wide enablement self-skip elsewhere.

Control Tower notes:

- SCPs are additive; never edit Control Tower `aws-guardrails-*` SCPs.
- SecurityHub is already enabled by Control Tower. In managed accounts, run
  `terraform import 'module.detection.aws_securityhub_account.this[0]' <region-arn>` once if apply
  reports the account is already registered.
- The account plane needs `log_bucket_name` and `log_bucket_arn` (from the management plane
  outputs) to deliver Config snapshots to the shared log bucket.

## Usage

```hcl
module "hardened" {
  source = "git::https://github.com/example/aws-hardened.git?ref=v1.0.0"

  management_account = false
  name_prefix        = "prod"
  tags               = { Environment = "production" }

  log_bucket_name = "acme-logs-123456789012-ap-southeast-3"
  log_bucket_arn  = "arn:aws:s3:::acme-logs-123456789012-ap-southeast-3"
}
```

See `examples/basic` for a complete standalone example.

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

- The log bucket name is auto-generated from prefix, account ID, and region on the
  management plane. Set `log_bucket_name` to override.
- Object Lock `COMPLIANCE` mode (default 6 years, `object_lock_retention_days`)
  makes log objects immutable; the bucket cannot be deleted until retention expires.
- `log_bucket_arn` is required on the account plane.
- Break-glass trust policy is deny-by-default (empty statement list); it must be
  flipped out-of-band before use, and every assumption fires an SNS alert.
- Config `RESTRICTED_COMMON_PORTS` / `RESTRICTED_SSH` run with AWS default ports;
  pass `config_rule_parameters` to customize.
