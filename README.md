# AWS Control Tower Account Vending

This repository vendors and reconciles AWS accounts through the native AWS
Control Tower Account Factory Service Catalog product. Every vended account
receives a mandatory per-account baseline through native OpenTofu.

## Features

- Declarative account requests in `02-accounts-creation/`.
- Immutable account identity fields: name, root email, and managed OU.
- Explicit OU moves, metadata/contact reconciliation, and failed-item reruns.
- Archive semantics for deleted requests: AWS accounts are never destroyed.
- Unmanaged-account discovery with an explicit ignore-list escape hatch.
- JSON bootstrap-failure reports that fail the pipeline and support targeted
  reruns.
- No CloudFormation, Lambda, AFT, CodeBuild, or CodePipeline.

## Out of scope

GuardDuty, Inspector, Macie, Security Hub, and organization-level hardening
(including SCPs, encryption policy, and detection configuration) are maintained
in a separate repository. This repository owns vending and the mandatory
per-account baseline only.

## Requirements

- OpenTofu `>= 1.8.0`.
- AWS Control Tower with Account Factory available through Service Catalog.
- AWS provider `hashicorp/aws` exactly pinned to `6.58.0`.
- GitLab OIDC credentials and the management/per-account roles required by the
  pipeline.
- The baseline's required contact and cross-account values for real deployments.

## Deployment order

1. `00-backend/` — create the encrypted, versioned, organization-restricted
   S3 state bucket once.
2. `01-management-init-role-and-hardening/` — establish management-account
   prerequisites once.
3. `02-accounts-creation/` — review and merge account request YAML files.
4. `pipeline/` — fixed pipeline roots are executed by GitLab; do not edit them
   manually.

The detailed operational procedure is in `docs/gitlab-deployment.md`. The
request schema and artifact ownership are defined in `ARCHITECTURE.md`.

## Local verification

```sh
tofu fmt -check -recursive
tofu init -backend=false
tofu validate
```

Run commands from the OpenTofu root being checked. Never run `tofu plan` or
`tofu apply` as a local verification step.
