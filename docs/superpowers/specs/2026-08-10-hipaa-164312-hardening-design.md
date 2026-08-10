# HIPAA §164.312 Hardening — Design

Date: 2026-08-10
Status: Approved (chat), pending written-spec review

## Context

`aws-hardened` is an OpenTofu module applying a HIPAA §164.312 security baseline to an AWS
organization built on Control Tower + IAM Identity Center + AWS Organizations. The org runs
deployments from a single repo: the management account provisions the organization plane, and
every other account runs the same module to provision its account plane.

This design covers tranche 1: identity, SCPs, audit, encryption, and threat detection. Network
segmentation, backups, SSM patching/inventory, ACM/ALB/CloudFront, ECR/Kyverno, and RDS instance
creation are deferred to tranche 2 (they require account topology inputs not yet available).

## Decisions

- **Module structure**: sub-modules per control family, composed by a root module with per-family
  `enabled` flags (option A, approved).
- **Deployment model**: one module, `management_account = true|false`. Org-plane families
  (SCP, SSO, org audit, org detection) self-skip when `false`. Per-account pipeline runs the same
  module in each account (option A, approved).
- **Region**: single primary region, default `ap-southeast-3` (Jakarta), overridable via `region`
  variable.
- **Control Tower posture**: SCPs are additive only. Never modify Control Tower `aws-guardrails-*`
  SCPs. SecurityHub is CT-managed; standards subscription may require one-time `tofu import` in
  managed accounts (documented in README).

## Repo Layout

```
aws-hardened/
├── main.tf               # root composition, per-family enabled flags
├── variables.tf          # shared inputs
├── outputs.tf
├── versions.tf           # tofu >= 1.8, aws 6.58.0 pinned
├── modules/
│   ├── identity/         # SSO, break-glass, IAM password policy
│   ├── scp/              # organization SCPs
│   ├── audit/            # org CloudTrail, Config, log bucket (Object Lock)
│   ├── encryption/       # KMS CMK, EBS default encryption, S3 account PAB
│   └── detection/        # GuardDuty, SecurityHub, Inspector2, Macie
├── examples/basic/
└── tests/
```

Existing root resources (S3 account PAB, IAM password policy, EBS default encryption, GuardDuty,
CloudTrail + log bucket) migrate into the family modules without losing behavior.

## Family Specs

### identity (both planes)

Management plane (`management_account = true`):
- SSO permission sets from a configurable map: defaults `read-only`
  (`arn:aws:iam::aws:policy/ReadOnlyAccess`), `security-audit`
  (`arn:aws:iam::aws:policy/SecurityAudit`), `break-glass` (narrow inline policy,
  `session_duration = "PT1H"`).
- SSO account assignments: `sso_group_arns` map, keyed by permission set name →
  list of Identity Center group ARNs. Group ARNs are required inputs (cannot be derived).

Account plane:
- IAM account password policy (existing `aws_iam_account_password_policy`, stays in this module).
- Break-glass: `aws_iam_role` with deny-by-default (empty) `assume_role_policy`, flipped
  out-of-band; narrowly scoped inline policy; `max_session_duration = 3600`.
- CloudWatch Event rule on `AssumeRole` for the break-glass role ARN → SNS topic for the
  mandatory 24-hour post-use review.

### scp (management plane only)

Five SCPs, each targeting the ePHI OU list from `ephp_ou_ids` variable:
1. `DenyIAMUserCreations` — deny `iam:CreateUser`, `iam:CreateAccessKey`; exception via
   `aws:PrincipalArn` for the break-glass role.
2. `RequireMFA` — deny `*` unless `aws:MultiFactorAuthPresent = true`; exceptions for AWS service
   principals and the break-glass role.
3. `DenyUnencryptedResources` — deny `s3:CreateBucket`, `ec2:CreateVolume`,
   `rds:CreateDBInstance` without encryption conditions
   (`s3:x-amz-server-side-encryption`/`ec2:Encrypted`/`rds:StorageEncrypted`).
4. `DenyPublicAdminPorts` — deny `ec2:AuthorizeSecurityGroupIngress`,
   `ec2:AuthorizeSecurityGroupEgress`, `ec2:RevokeSecurityGroupIngress` when
   `ec2:SourceIp` is in `["0.0.0.0/0", "::/0"]` and port range overlaps 22/3389/1433/3306.
5. `DenyIAMUserInlinePolicies` — deny `iam:PutUserPolicy`, `iam:AttachUserPolicy`,
   `iam:CreateUser` (drift toward shared/inline-policy users).

### audit (both planes)

Management plane:
- Org CloudTrail: `is_organization_trail = true`, `include_global_service_events = true`,
  `enable_log_file_validation = true`, `aws_service_principal = "cloudtrail.amazonaws.com"`,
  event selectors for S3 + DynamoDB data events.
- Config delegated admin (account ID input).

Account plane:
- Config recorder + delivery channel to the log bucket; bucket policy grants `config.amazonaws.com`.
- Managed Config rules: `IAM_POLICY_NO_STATEMENTS_WITH_ADMIN_ACCESS`,
  `IAM_USER_NO_POLICIES_CHECK`, `ENCRYPTED_VOLUMES`, `S3_BUCKET_SERVER_SIDE_ENCRYPTION_ENABLED`,
  `RDS_STORAGE_ENCRYPTED`, `IAM_USER_MFA_ENABLED`, `ROOT_ACCOUNT_MFA_ENABLED`,
  `VPC_DEFAULT_SECURITY_GROUP_CLOSED`, `RESTRICTED_SSH`, `RESTRICTED_COMMON_PORTS`,
  `ALB_HTTP_TO_HTTPS_REDIRECTION_CHECK`, `EC2_INSTANCE_MANAGED_BY_SSM`.
- HIPAA conformance pack via AWS-managed `template_s3_uri` (no vendored 2,000-line template).
- Log bucket (owned by the audit module): KMS-SSE, versioning, Object Lock `COMPLIANCE` mode
  6 years (default, configurable), lifecycle expire after retention, S3 access logging, public
  access block, bucket policy for CloudTrail + Config.

### encryption (account plane only)

- KMS CMK: `enable_key_rotation = true`, deletion window 30 days, key policy scoped to account root
  plus configurable `kms_user_arns`/`kms_admin_arns`.
- EBS default encryption (existing `aws_ebs_encryption_by_default`).
- S3 account public access block (existing, stays in this module).

### detection (both planes)

Management plane:
- GuardDuty delegated admin + organization configuration.
- SecurityHub organization configuration.
- Inspector2 organization enablement.
- Macie organization admin.

Account plane:
- GuardDuty detector (`FIFTEEN_MINUTES`) + malware protection plan (EC2/S3).
- Macie account + classification job.
- SecurityHub standards subscriptions (`aws-foundational-security-best-practices`,
  `cis-aws-foundations-benchmark`, `hipaa`).

## Shared Inputs

- `management_account` (bool, required)
- `region` (default `ap-southeast-3`)
- `name_prefix`, `tags`
- `ephp_ou_ids` (list, management plane)
- `sso_group_arns` (map, management plane)
- `sso_permission_sets` (map with defaults, management plane)
- `break_glass_role_name`, `sns_*` topic settings
- `log_bucket_name` (default: `{prefix}-{account_id}-{region}-logs`)
- `object_lock_retention_days` (default 2190)
- `cloudtrail_retention_days` (default 90, lifecycle only — Object Lock governs legal retention)
- `kms_admin_arns`, `kms_user_arns`

## Success Criteria

- `tofu fmt` clean, `tofu validate` passes, `tofu test` smoke test green (mock provider).
- Org-plane resources only when `management_account = true`; account-plane resources only when
  `false` — verified by plan output in tests.
- No drift against the approved SCP set; each SCP present exactly once.
- Existing scaffold behavior preserved (S3 PAB, password policy, EBS encryption, GuardDuty,
  CloudTrail) after migration into family modules.

## Deferred to Tranche 2

Network segmentation/VPC endpoints (§10, §13, §18), backups (§7), SSM patching/inventory/State
Manager (§14, §17, §19), ALB/ACM/CloudFront (§11, §12), ECR/Kyverno (§16), RDS instance creation,
WorkSpaces golden images.
