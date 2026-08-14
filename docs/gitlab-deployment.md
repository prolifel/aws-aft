# Deploying to every account via GitLab CI/CD

Replaces the AFT runbook: no AFT, no CodeBuild, no CodePipeline. GitLab CI/CD
drives the whole lifecycle. See the design spec
`docs/superpowers/specs/2026-08-14-gitlab-native-design.md`.

## How it fits together

| Folder | When | Who runs it |
|---|---|---|
| `00-backend/` | once, first | you, manually |
| `01-management-init-role-and-hardening/` | once, second | you, manually |
| `accounts/*.yaml` | every account change | GitLab `provision` job |
| `02-account-init-role/` | per account, automatically | GitLab `customize` job |
| `03-account-hardening/` | per account, automatically | GitLab `customize` job |

You only ever touch two things by hand: apply `00-backend` + `01-...` once,
then add/edit `accounts/*.yaml`. Everything else is the pipeline.

## Step 0: state bucket (manual, once)

```sh
cd 00-backend && tofu init && tofu apply
```

Takes `output.state_bucket_name` and paste it into the `bucket` line of
`01-management-init-role-and-hardening/versions.tf`,
`02-account-init-role/versions.tf`, and `03-account-hardening/versions.tf`.
No lock table — a single pipeline (`resource_group`) already serializes runs.

## Step 1: management init + hardening (manual, once)

Set the required variables (GitLab URL, project path, ePHI OU IDs) via
`terraform.tfvars` or `-var`, then:

```sh
cd 01-management-init-role-and-hardening
tofu init && tofu apply
```

This creates: org hardening (SCPs, SSO, org CloudTrail, delegated admins),
the `gitlab-ci` role, and the handoff config bucket with `config.json`.
Take `output.gitlab_ci_role_arn` and `output.state_bucket_name` — they become
the GitLab `CI_ROLE_ARN` and `CONFIG_BUCKET_ARN` variables.

## Step 2: GitLab variables + pipeline

Set CI/CD variables on the project:

- `CI_ROLE_ARN` — from Step 1 output
- `CONFIG_BUCKET_ARN` — `arn:aws:s3:::<config-bucket>` from Step 1 output
- optional `DELETE_DEFAULT_VPCS=1` — deletes default VPCs in every account
- optional `ALLOW_TERMINATE=1` — allow account deletion via YAML removal

Push the repo with `.gitlab-ci.yml`. The pipeline runs on push and on
schedule (drift + inventory).

## Step 3: backfill existing accounts

```sh
scripts/account-inventory.sh --aft-requests accounts
```

Commit the generated `accounts/*.yaml` files and merge. `provision` skips
Service Catalog for accounts that already exist; `customize` bootstraps the
per-account role and applies the hardening.

## Step 4: new accounts

Add `accounts/<name>.yaml` in an MR:

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

`provision` calls `ProvisionProduct` (or `UpdateProvisionedProduct` for
OU/tag changes), polls until the account is `AVAILABLE`, then `customize`
runs `02-account-init-role` (creates the `hardened-deploy` role inside the
new account) and `03-account-hardening` (applies the module). Delete the YAML
to remove the account.

## How one account gets hardened

1. `provision` creates the account via Service Catalog Account Factory.
2. `customize` assumes `AWSControlTowerExecution` in the new account (the
   only role Control Tower creates there) and applies `02-account-init-role`,
   which creates `hardened-deploy` trusting the `gitlab-ci` role.
3. `customize` re-assumes as `hardened-deploy` and applies
   `03-account-hardening` with per-account state
   (`<account_id>/account-hardening.tfstate`).

Both roots are per-account: same code, one state file per account.

## Remove AFT

1. Run the pipeline once so every account is hardened outside AFT.
2. `tofu destroy` the AFT core in the AFT management account.
3. Optional: delete the AFT management account.

## Verify

- `curl https://gitlab.example.com/.well-known/openid-configuration` and
  `/oauth/discovery/keys` return JSON (see `docs/gitlab-oidc/`).
- A scheduled pipeline completes: management apply, customize for every
  account, inventory report.
- `scripts/account-inventory.sh --inventory` shows every account with the
  expected SCPs and `management_account=false`.
- No CodeBuild/CodePipeline resources remain in the AFT management account.
