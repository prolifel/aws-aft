# Account requests

One declarative YAML file per account. See `template.yaml` for the full schema.

- `account_name`, `email`, `managed_org_unit` are identity: immutable after vending.
- OU moves are explicit, reviewed operations.
- Deleting a request archives the account; it never deletes the AWS account.
- Metadata (`owner`, `environment`, `cost_center`, `regions`, `tags`) reconciles.
- Accounts present in AWS with no request are validation failures unless listed in `.ignored-accounts.yaml`.

Lifecycle and pipeline: `docs/gitlab-deployment.md`.
