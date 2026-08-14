# Design: GitLab-native account lifecycle (drop AFT, no CodeBuild)

Date: 2026-08-14
Status: Approved for implementation
Scope: aws-hardened module repo

## Problem

The AFT deployment (`aft/main.tf`) depends on AWS CodeBuild/CodePipeline: four
pipelines (account request, provisioning customizations, account
customizations, global customizations) plus the Lambda layer build. The
operator wants the pipeline layer to run in GitLab CI/CD (self-hosted
GitLab), with zero AWS CodeBuild/CodePipeline.

## Decision

Drop AFT entirely. GitLab CI/CD orchestrates the account lifecycle:
Control Tower Account Factory (Service Catalog) for account create/update/
delete, and the aws-hardened module for the management plane and per-account
plane. OIDC federation (`assume-role-with-web-identity`) replaces CodeBuild
service roles. The account request repo, DDB queue, Lambdas, and Step
Functions go away; Git MRs and pipeline runs become the request/audit layer.

## Goals

- Zero CodeBuild/CodePipeline/Step Functions/Lambda in the deployment.
- GitLab CI/CD drives: account create/update/delete, per-account hardening,
  management-plane drift runs.
- Self-hosted GitLab OIDC works with AWS (issuer reachable via
  cloudflared + Nginx Proxy Manager, path-filtered to OIDC endpoints only).
- Existing-account backfill unchanged in spirit: inventory script emits
  request files, one pipeline run hardens all accounts.

## Non-Goals

- No fork/maintenance of `terraform-aws-control_tower_account_factory` or
  `aws-aft-core-framework`.
- No per-account SSO assignment wrapper (module takes a single
  `sso_target_account_id`; unchanged).
- No replacement for AFT's built-in features that the operator does not use
  (enterprise support, VPC, metrics, SNS reporting).
- No changes to the log bucket policy (owned by the audit module).

## Architecture

### Accounts and roles

1. **Org management account** — hosts the management plane (SCPs, SSO, org
   CloudTrail + Object Lock bucket, Config/GuardDuty/Inspector2/Macie
   delegated admins), the handoff config bucket, and the new `modules/ci/`
   OIDC provider + `gitlab-ci` role.
2. **Member accounts** — run the account plane (`management_account = false`)
   through a per-account `hardened-deploy` role.
3. **No AFT management account** — destroyed during migration; optional:
   delete the account.

### OIDC chain

```
GitLab CI job (id_token, aud=sts.amazonaws.com)
  -> assume-role-with-web-identity -> gitlab-ci role (org mgmt account)
     -> sts:AssumeRole -> AWSControlTowerExecution (new account, bootstrap)
        -> apply bootstrap root -> creates hardened-deploy role
     -> sts:AssumeRole -> hardened-deploy (subsequent account-plane runs)
```

- `AWSControlTowerExecution` exists in every Control Tower-managed account at
  creation; it is the only way into a brand-new account before any of our
  roles exist. Used once per account to bootstrap `hardened-deploy`, then
  account-plane runs use `hardened-deploy` directly.
- Dedicated `hardened-deploy` (trust: `gitlab-ci` role in mgmt account) is
  preferred over reusing `AWSControlTowerExecution` on every run: scoped
  trust, stable against Control Tower-managed role changes.

### OIDC discovery ingress (public AWS fetch only)

AWS fetches the discovery document and JWKS at assume-role time, so only
`/.well-known/*` and `/oauth/discovery/keys` are exposed. TLS terminates at
Cloudflare; Nginx Proxy Manager and GitLab stay plain HTTP internally.
GitLab `external_url` is the public HTTPS host so the discovery document
contains the correct `issuer` and `jwks_uri`.

```
AWS -> https://gitlab.example.com/.well-known/openid-configuration
    -> https://gitlab.example.com/oauth/discovery/keys
    -> cloudflared tunnel (path-filtered)
    -> Nginx Proxy Manager (path-based locations)
    -> GitLab Rails (plain HTTP, external_url https://gitlab.example.com)
```

### AWS side: new `modules/ci/` family module

Enabled with `management_account = true` via new root variable
`ci_enabled` (default `false`). Resources:

- `aws_iam_openid_connect_provider` — url `https://gitlab.example.com`,
  client id list `["sts.amazonaws.com"]`. `thumbprint_list` left empty
  (AWS auto-fetches; Cloudflare serves a public CA cert). If AWS rejects
  the auto-fetch, capture the SHA-1 thumbprint of the discovery endpoint
  cert and pass it via `oidc_thumbprint` variable (documented fallback,
  not a design change).
- IAM role `gitlab-ci` — trust:
  - `oidc:aud = sts.amazonaws.com`
  - `oidc:sub = project_path:<group>/<project>:ref_type:branch:ref:main`
- Inline policies:
  - Service Catalog: `ProvisionProduct`, `UpdateProvisionedProduct`,
    `TerminateProvisionedProduct`, `DescribeProvisionedProduct`,
    `ListProvisioningArtifacts`, `SearchProductsAsAdmin` (Account Factory
    product in the org mgmt account).
  - Organizations/SSO/CloudTrail/Config/GuardDuty/Inspector2/Macie: same
    scope as the management-plane apply.
  - Config bucket: `s3:GetObject` (handoff `config.json`).
  - `sts:AssumeRole` into member accounts (`AWSControlTowerExecution`,
    `hardened-deploy`).

Variables (operator fills in):

| Variable | Meaning |
|---|---|
| `gitlab_url` | issuer base, e.g. `https://gitlab.example.com` |
| `gitlab_project_path` | e.g. `prolifel/aws-aft` (used in `sub` trust condition) |
| `gitlab_branch` | default `main` |
| `oidc_thumbprint` | optional fallback, default `null` |

### GitLab CI/CD pipeline (`.gitlab-ci.yml`, delivered as template)

Stages: `account-factory`, `management-plane`, `account-plane`, `inventory`.

Shared OIDC bootstrap (hidden job with `id_tokens`):

```yaml
.aws-oidc:
  id_tokens:
    OIDC_TOKEN:
      aud: sts.amazonaws.com
  before_script:
    - |
      creds=$(aws sts assume-role-with-web-identity \
        --role-arn "$CI_ROLE_ARN" --role-session-name "ci-$CI_PIPELINE_ID" \
        --web-identity-token-file "$STS_WEB_IDENTITY_TOKEN_FILE")
      export AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r .Credentials.AccessKeyId)
      export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r .Credentials.SecretAccessKey)
      export AWS_SESSION_TOKEN=$(echo "$creds" | jq -r .Credentials.SessionToken)
```

- `provision` job — push to `accounts/**`: validate YAML, diff against AWS
  (existing provisioned products), then per account:
  - missing product -> `ProvisionProduct`
  - exists -> `UpdateProvisionedProduct` (OU + tags only)
  - request file deleted -> `TerminateProvisionedProduct`
  - poll `DescribeProvisionedProduct` until `AVAILABLE`
  `resource_group: account-factory` serializes runs (mirrors AFT FIFO).
  Emits `account_ids.txt` artifact.
- `customize` job — `needs: [provision]`, reads `account_ids.txt`, per
  account: bootstrap `hardened-deploy` if missing, then `tofu apply`
  aws-hardened (`management_account = false`) with handoff `config.json`.
  Per-account state in the account-plane root's backend.
- `management-plane` job — schedule + manual + push to `management/**`:
  `tofu apply` mgmt plane, writes handoff `config.json`.
- `drift` job — schedule: re-apply account plane for all existing accounts.
- `inventory` job — schedule: `scripts/account-inventory.sh` report.

### Account request format (YAML, Git-native)

Replaces AFT terraform request modules. `scripts/account-inventory.sh
--aft-requests` emits this format (extended with SSO fields + tags):

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

- File per account under `accounts/<account_id_or_name>.yaml`.
- Existing accounts (present in Organizations): backfill files are
  create-only; `provision` skips the Service Catalog step for them and
  `customize` still runs.
- Delete = delete the YAML in an MR. Terminating the Account Factory product
  removes the account from Control Tower (destructive; MR review is the
  gate).

### Repo layout

- This repo: `modules/ci/`, `.gitlab-ci.yml` template,
  `docs/gitlab-deployment.md` (replaces `docs/aft-deployment.md`),
  `docs/gitlab-oidc/` (cloudflared + NPM configs), inventory script updated,
  `aft/` directory removed.
- Deployment repo (operator's, e.g. `prolifel/aws-aft`): real
  `.gitlab-ci.yml`, `accounts/*.yaml`, management-plane root
  (`management/`), account-plane root (`account-plane/`), bootstrap root
  (`account-bootstrap/`).

### Ingress configs (delivered in `docs/gitlab-oidc/`)

cloudflared `config.yml`:

```yaml
tunnel: <TUNNEL_ID>
credentials-file: /etc/cloudflared/<TUNNEL_ID>.json
ingress:
  - hostname: gitlab.example.com
    path: /.well-known/*
    service: http://nginx-proxy-manager
  - hostname: gitlab.example.com
    path: /oauth/discovery/keys
    service: http://nginx-proxy-manager
  - service: http_status:404
```

Nginx Proxy Manager — proxy host `gitlab.example.com`, websockets on, two
custom locations: `/.well-known/` -> `http://gitlab:80`,
`/oauth/discovery/keys` -> `http://gitlab:80`. Block common exploits: off
(tunnel already filters; avoids false positives on OIDC responses).
Equivalent generated conf (`proxy-host.conf`):

```nginx
server {
  set $forward_scheme http;
  set $server "gitlab";
  set $port 80;
  listen 80;
  server_name gitlab.example.com;

  location /.well-known/ {
    proxy_pass http://gitlab:80;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
  location /oauth/discovery/keys {
    proxy_pass http://gitlab:80;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  }
  location / { return 404; }
}
```

GitLab `gitlab.rb`: `external_url 'https://gitlab.example.com'`.

## Migration

1. Apply `modules/ci/` in the org mgmt account (OIDC provider, `gitlab-ci`
   role) — requires the ingress + GitLab OIDC discovery to be live first.
2. Scaffold the deployment repo: `.gitlab-ci.yml`, `accounts/`,
   `management/`, `account-plane/`, `account-bootstrap/`; wire
   `CI_ROLE_ARN`.
3. Backfill: `scripts/account-inventory.sh --aft-requests` -> commit files
   -> pipeline hardens all existing accounts.
4. New accounts: MR adding `accounts/*.yaml`.
5. Remove AFT: `tofu destroy` the AFT core in the AFT mgmt account, delete
   `aft/` from this repo, optional: delete the AFT mgmt account.
6. Verify per-account `hardened-deploy` bootstrapped and management-plane
   handoff `config.json` readable by the account-plane jobs.

## Verification

- `tofu validate` + `tofu test` stay green (module change is additive:
  new `ci_enabled` variable + `modules/ci/`).
- `tofu fmt` clean.
- Ingress: `curl https://gitlab.example.com/.well-known/openid-configuration`
  and `/oauth/discovery/keys` return GitLab JSON; any other path returns 404.
- OIDC: pipeline job assumes `gitlab-ci` role; management-plane apply runs;
  account-plane apply runs in one backfill account; inventory matrix shows
  the expected SCPs.
- AFT removal: no CodeBuild/CodePipeline resources remain in the AFT
  management account.

## Deliverables in this repo

- `modules/ci/` — OIDC provider + `gitlab-ci` role (+ root wiring +
  `ci_enabled` variable).
- `.gitlab-ci.yml` — pipeline template.
- `docs/gitlab-oidc/` — cloudflared config, NPM proxy-host conf, notes.
- `docs/gitlab-deployment.md` — runbook; replaces `docs/aft-deployment.md`.
- `scripts/account-inventory.sh` — `--aft-requests` emits the new YAML
  format.
- `aft/` removed.
- This design spec.

## Out of scope (documented, not built)

- Cloudflare tunnel credentials/NPM deployment itself (operator-owned infra).
- GitLab group/project provisioning and runner setup.
- Deletion of the AFT management account (operator action).
