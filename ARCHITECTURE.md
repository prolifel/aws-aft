# AWS Account Vending Architecture

## Purpose

This repository is a Control Tower account-vending system. It creates and
reconciles AWS accounts through the native AWS Control Tower Account Factory
Service Catalog product, then applies one mandatory per-account baseline with
native OpenTofu.

This repository does not enable GuardDuty, Inspector, Macie, or Security Hub,
and does not own organization-level hardening, SCPs, encryption policy, or
detection configuration. Those concerns belong to a separate repository.

There is no CloudFormation, Lambda, CodeBuild, CodePipeline, or AFT framework
in this design.

## Account request contract

Each active request is one YAML file under `02-accounts-creation/`:

```yaml
account_name: "production-app"
email: "production-app@example.com"
managed_org_unit: "production"
owner: "platform"
environment: "production"
cost_center: "CC-1234"
regions:
  - "ap-southeast-3"
tags:
  Environment: "production"
  CostCenter: "CC-1234"
```

The required fields are `account_name`, `email`, `managed_org_unit`, `owner`,
`environment`, `cost_center`, `regions`, and `tags`. `account_name`, `email`,
and `managed_org_unit` are identity fields: they are immutable after vending.
An OU change is an explicit move operation, never an implicit identity edit.

Deleting a request archives the AWS account from active management; it never
destroys the account. Metadata and alternate contacts reconcile on reruns.
Reruns reconcile only failed items. AWS accounts discovered without a matching
request fail validation unless they are listed in the explicit ignore list.

## Domain-to-artifact map

| Domain | Authoritative artifact | Responsibility |
|---|---|---|
| State backend | `00-backend/` | Creates the encrypted, versioned, organization-restricted S3 state bucket. |
| Management bootstrap | `01-management-init-role-and-hardening/` | One-time management-account prerequisites for GitLab and Control Tower vending. |
| Account requests | `02-accounts-creation/*.yaml` | Declarative account-request inputs; edited through review. |
| Account vending | `modules/account-vending/` and `pipeline/account-vending/` | Submits Control Tower Account Factory Service Catalog provisioning operations. |
| Per-account baseline | `modules/account-bootstrap/` | Applies the mandatory native OpenTofu baseline after an account exists. |
| Request validation and reconciliation | `scripts/account-factory.sh` | Validates schema and identity rules, discovers drift, and runs vending operations. |
| Account discovery/validation | `scripts/validate-accounts.sh` | Validates request schema, unique/immutable identity, ignore list, and org coverage. |
| Baseline orchestration | `scripts/account-bootstrap.sh` | Applies the per-account baseline and emits machine-readable bootstrap failure results. |
| CI orchestration | `.gitlab-ci.yml` | Runs validation, provisioning, bootstrap, and scheduled inventory. |

`modules/account-vending/` and `modules/account-bootstrap/` are the only
functional module domains retained in this repository.

## Pipeline stages

1. **Validate** — parse every request, enforce the request schema and immutable
   identity rules, discover unmanaged accounts, and fail unless each account is
   requested or explicitly ignored.
2. **Provision** — reconcile changed or failed requests through the Control
   Tower Account Factory Service Catalog product. Existing accounts are not
   re-vended unnecessarily.
3. **Bootstrap** — assume the per-account deployment role and apply the
   mandatory baseline with OpenTofu. A failed bootstrap writes a JSON report,
   publishes it as a job artifact, and fails the job.
4. **Inventory** — scheduled discovery compares organization accounts with
   requests and the ignore list.

A deleted request enters archive semantics during validation/reconciliation;
no pipeline job destroys an AWS account. A failed provisioning or bootstrap
operation is retried by a targeted rerun. Bootstrap does not repeat successful
items.

## Verification commands

Run these commands from each changed OpenTofu domain:

```sh
tofu fmt -check -recursive

tofu init -backend=false
tofu validate
```

The state root can be initialized normally only when applying it for the first
time. Do not run `tofu plan` or `tofu apply` in routine verification of this
repository.

## Deferred multi-region baseline

The current mandatory baseline is applied in the account's configured primary
region, `ap-southeast-3`. Multi-region baseline coverage is intentionally
deferred. When added, it must be designed as an explicit contract change,
including region selection, provider aliases, state layout, idempotent rerun
semantics, and tests; it must not be inferred from the request's `regions` list.
