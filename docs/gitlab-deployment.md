# GitLab account-vending runbook

This runbook covers the GitLab pipeline for account requests. It replaces the
previous hardening/AFT workflow. Security-service enablement
(GuardDuty, Inspector, Macie, Security Hub) and org hardening are managed by a
separate repository and are out of scope here.

## CI/CD variables

- `CI_ROLE_ARN` — ARN of the gitlab-ci role (output of `01-management-init-role-and-hardening`)
- `STATE_BUCKET` — central state bucket (output of `00-backend`)
- `STATE_REGION` — state bucket region (default `ap-southeast-3`)
- `ACCOUNT_FACTORY_PRODUCT_ID` — Service Catalog product ID of Control Tower Account Factory
- Bootstrap contact vars — `security_contact_name`, `security_contact_email`,
  `security_contact_phone`, `billing_contact_name`, `billing_contact_email`,
  `billing_contact_phone`, `operations_contact_name`, `operations_contact_email`,
  `operations_contact_phone` (central org constants; written to
  `pipeline/account-bootstrap/base.tfvars` by `scripts/account-bootstrap.sh`)

## Pipeline stages

1. `validate` — runs on MR and push changes to `02-accounts-creation/**`.
   Validates every request against the schema, unique/immutable identity, the
   ignore list, and (in CI) AWS Organizations coverage. Writes
   `account-reports/validation.json`.
2. `provision` — runs after merge on push. `scripts/account-factory.sh` vendors
   each account that is not already present (matched by email) via
   `pipeline/account-vending`. Never re-vends. Writes
   `account-reports/account-factory.json`.
3. `bootstrap` — runs after provision. `scripts/account-bootstrap.sh` applies
   the mandatory baseline via `pipeline/account-bootstrap` as
   `AWSControlTowerExecution`. On failure it emits
   `account-reports/bootstrap-<account>.json` with
   `"status":"completed-with-bootstrap-failures"` and fails the job.

## Lifecycle semantics

- Deleting a request archives the account; the AWS account is never destroyed.
- `account_name`, `email`, and `managed_org_unit` are immutable; OU moves are
  explicit reviewed operations.
- Metadata (owner, environment, cost center, regions, tags) and alternate
  contacts reconcile on rerun.
- Reruns reconcile only failed items and never re-vend an existing account.
- AWS accounts without a matching request fail validation unless listed in
  `02-accounts-creation/.ignored-accounts.yaml`.

## Rerun and rollback

- Rerun the failed job to reconcile only the failed bootstrap items.
- To roll back a request change, edit or delete the request YAML in a new MR
  and let validation + provision reconcile; deletion archives, never destroys.
- Stuck provisioning: inspect the Service Catalog provisioned product in the
  management account, then rerun `scripts/account-factory.sh`; idempotency
  prevents duplicate account creation.
