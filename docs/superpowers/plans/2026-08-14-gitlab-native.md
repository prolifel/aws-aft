# GitLab-Native Account Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the AFT deployment with a GitLab-native account lifecycle: a `modules/ci/` OIDC module, a `.gitlab-ci.yml` pipeline template, provisioning scripts, and runbook — zero AWS CodeBuild/CodePipeline.

**Architecture:** GitLab CI jobs assume an OIDC-federated `gitlab-ci` role in the org management account, then either call Service Catalog Account Factory directly (account create/update/terminate) or assume a per-account `hardened-deploy` role (bootstrap via `AWSControlTowerExecution`) to run the aws-hardened module's account plane. A cloudflared tunnel + Nginx Proxy Manager expose only GitLab's OIDC discovery endpoints to AWS. AFT, its account, its four pipelines, and its Lambda layer are deleted.

**Tech Stack:** OpenTofu (>= 1.8.0), AWS provider `6.58.0`, AWS IAM OIDC, Service Catalog Account Factory, Organizations, GitLab CI/CD, cloudflared, Nginx Proxy Manager, Bash + `aws` CLI + `jq`.

**Spec:** `docs/superpowers/specs/2026-08-14-gitlab-native-design.md`

---

## File Structure

- Create: `modules/ci/main.tf` — OIDC provider, `gitlab-ci` role, 4 inline policies.
- Create: `modules/ci/variables.tf` — module inputs.
- Create: `modules/ci/outputs.tf` — role ARN + provider ARN.
- Modify: `variables.tf` (root) — `ci_enabled`, `gitlab_url`, `gitlab_project_path`, `gitlab_branch`, `oidc_thumbprint`, `config_bucket_arn`.
- Modify: `main.tf` (root) — `module "ci"`.
- Modify: `outputs.tf` (root) — `gitlab_ci_role_arn`.
- Modify: `tests/account_baseline.tftest.hcl` — mock override + `ci_management_plane` run + account-plane negative assert.
- Modify: `scripts/account-inventory.sh` — `--aft-requests` emits the GitLab-native YAML.
- Modify: `tests/inventory_test.sh` — new YAML expectations.
- Create: `scripts/account-factory.sh` — validate/diff/provision/update/terminate/poll against Account Factory.
- Create: `scripts/account-plane.sh` — bootstrap `hardened-deploy`, run account-plane tofu.
- Create: `.gitlab-ci.yml` — pipeline template.
- Create: `ci/oidc.sh` — OIDC credential export sourced by jobs.
- Create: `docs/gitlab-oidc/cloudflared.yml`, `docs/gitlab-oidc/nginx-proxy-manager.conf`, `docs/gitlab-oidc/README.md`.
- Create: `docs/gitlab-deployment.md`; delete: `docs/aft-deployment.md`, `aft/main.tf`, `aft/variables.tf`, `aft/aft-sandbox/main.tf`.

Operated placeholders (documented, not TBDs): `gitlab.example.com` (issuer), `prolifel/aws-aft` (project path), `CI_ROLE_ARN`, `CONFIG_BUCKET_ARN`.

---

### Task 1: `modules/ci/` OIDC module + root wiring + test

**Files:**
- Create: `modules/ci/main.tf`
- Create: `modules/ci/variables.tf`
- Create: `modules/ci/outputs.tf`
- Modify: `variables.tf`
- Modify: `main.tf`
- Modify: `outputs.tf`
- Modify: `tests/account_baseline.tftest.hcl`

- [ ] **Step 1: Create `modules/ci/variables.tf`**

```hcl
variable "enabled" {
  description = "Whether to create GitLab CI OIDC resources."
  type        = bool
  default     = true
}

variable "management_account" {
  description = "Whether this module runs in the organization management account."
  type        = bool
}

variable "name_prefix" {
  description = "Prefix for the GitLab CI role name."
  type        = string
}

variable "tags" {
  description = "Tags applied to the GitLab CI role."
  type        = map(string)
  default     = {}
}

variable "gitlab_url" {
  description = "GitLab OIDC issuer base URL, e.g. https://gitlab.example.com."
  type        = string
  nullable    = false
}

variable "gitlab_project_path" {
  description = "GitLab project path for the OIDC sub trust condition, e.g. prolifel/aws-aft."
  type        = string
  nullable    = false
}

variable "gitlab_branch" {
  description = "Branch allowed to assume the GitLab CI role."
  type        = string
  default     = "main"
}

variable "oidc_thumbprint" {
  description = "Optional SHA-1 thumbprint of the OIDC issuer cert. Empty lets AWS auto-fetch."
  type        = string
  default     = null
}

variable "deploy_role_name" {
  description = "Per-account role name the GitLab CI role may assume."
  type        = string
  default     = "hardened-deploy"
}

variable "config_bucket_arn" {
  description = "ARN of the handoff config bucket. Empty skips the s3:GetObject policy."
  type        = string
  default     = ""
}
```

- [ ] **Step 2: Create `modules/ci/main.tf`**

```hcl
locals {
  ci_enabled = var.enabled && var.management_account
  oidc_host  = replace(var.gitlab_url, "https://", "")
}

resource "aws_iam_openid_connect_provider" "gitlab" {
  count = local.ci_enabled ? 1 : 0

  url             = var.gitlab_url
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = var.oidc_thumbprint != null ? [var.oidc_thumbprint] : []
}

data "aws_iam_policy_document" "gitlab_ci_trust" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.gitlab[0].arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "${local.oidc_host}:sub"
      values   = ["project_path:${var.gitlab_project_path}:ref_type:branch:ref:${var.gitlab_branch}"]
    }
  }
}

resource "aws_iam_role" "gitlab_ci" {
  count = local.ci_enabled ? 1 : 0

  name               = "${var.name_prefix}-gitlab-ci"
  assume_role_policy = data.aws_iam_policy_document.gitlab_ci_trust[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "servicecatalog" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "servicecatalog:DescribeProduct",
      "servicecatalog:DescribeProductAsAdmin",
      "servicecatalog:DescribeProvisionedProduct",
      "servicecatalog:ListProvisioningArtifacts",
      "servicecatalog:ProvisionProduct",
      "servicecatalog:SearchProductsAsAdmin",
      "servicecatalog:TerminateProvisionedProduct",
      "servicecatalog:UpdateProvisionedProduct",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "management_plane" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "cloudtrail:*",
      "config:*",
      "ec2:*",
      "guardduty:*",
      "iam:*",
      "identitystore:*",
      "inspector2:*",
      "kms:*",
      "logs:*",
      "macie2:*",
      "organizations:*",
      "s3:*",
      "securityhub:*",
      "sns:*",
      "sso-admin:*",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "config_bucket" {
  count = local.ci_enabled && var.config_bucket_arn != "" ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.config_bucket_arn}/*"]
  }
}

data "aws_iam_policy_document" "cross_account" {
  count = local.ci_enabled ? 1 : 0

  statement {
    effect    = "Allow"
    actions   = ["sts:AssumeRole"]
    resources = [
      "arn:aws:iam::*:role/AWSControlTowerExecution",
      "arn:aws:iam::*:role/${var.deploy_role_name}",
    ]
  }
}

resource "aws_iam_role_policy" "servicecatalog" {
  count = local.ci_enabled ? 1 : 0

  name   = "servicecatalog"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.servicecatalog[0].json
}

resource "aws_iam_role_policy" "management_plane" {
  count = local.ci_enabled ? 1 : 0

  name   = "management-plane"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.management_plane[0].json
}

resource "aws_iam_role_policy" "config_bucket" {
  count = local.ci_enabled && var.config_bucket_arn != "" ? 1 : 0

  name   = "config-bucket"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.config_bucket[0].json
}

resource "aws_iam_role_policy" "cross_account" {
  count = local.ci_enabled ? 1 : 0

  name   = "cross-account"
  role   = aws_iam_role.gitlab_ci[0].name
  policy = data.aws_iam_policy_document.cross_account[0].json
}
```

- [ ] **Step 3: Create `modules/ci/outputs.tf`**

```hcl
output "gitlab_ci_role_arn" {
  description = "ARN of the GitLab CI role."
  value       = try(aws_iam_role.gitlab_ci[0].arn, "")
}

output "oidc_provider_arn" {
  description = "ARN of the GitLab OIDC provider."
  value       = try(aws_iam_openid_connect_provider.gitlab[0].arn, "")
}
```

- [ ] **Step 4: Wire the module into the root `variables.tf`**

Append after the `management_account` variable:

```hcl
variable "ci_enabled" {
  description = "Whether to create GitLab CI OIDC resources (management account only)."
  type        = bool
  default     = false
}

variable "gitlab_url" {
  description = "GitLab OIDC issuer base URL, e.g. https://gitlab.example.com."
  type        = string
  default     = ""
}

variable "gitlab_project_path" {
  description = "GitLab project path for the CI trust condition, e.g. prolifel/aws-aft."
  type        = string
  default     = ""
}

variable "gitlab_branch" {
  description = "Branch allowed to assume the GitLab CI role."
  type        = string
  default     = "main"
}

variable "oidc_thumbprint" {
  description = "Optional SHA-1 thumbprint of the GitLab OIDC issuer cert."
  type        = string
  default     = null
}

variable "config_bucket_arn" {
  description = "ARN of the handoff config bucket used by account-plane jobs."
  type        = string
  default     = ""
}
```

- [ ] **Step 5: Wire the module into the root `main.tf`**

Append after the `module "detection"` block:

```hcl
module "ci" {
  source = "./modules/ci"

  enabled             = var.ci_enabled
  management_account  = var.management_account
  name_prefix         = var.name_prefix
  tags                = var.tags
  gitlab_url          = var.gitlab_url
  gitlab_project_path = var.gitlab_project_path
  gitlab_branch       = var.gitlab_branch
  oidc_thumbprint     = var.oidc_thumbprint
  config_bucket_arn   = var.config_bucket_arn
}
```

- [ ] **Step 6: Add the root output to `outputs.tf`**

Append:

```hcl
output "gitlab_ci_role_arn" {
  description = "ARN of the GitLab CI role."
  value       = module.ci.gitlab_ci_role_arn
}
```

- [ ] **Step 7: Extend `tests/account_baseline.tftest.hcl`**

Add a mock override inside the existing `mock_provider "aws"` block (after the `aws_iam_role.config` override):

```hcl
  override_resource {
    target = module.ci.aws_iam_role.gitlab_ci[0]
    values = {
      arn = "arn:aws:iam::123456789012:role/test-gitlab-ci"
    }
  }
```

Add this run block after the `management_plane` run:

```hcl
run "ci_management_plane" {
  command = apply

  variables {
    management_account    = true
    name_prefix           = "test"
    ci_enabled            = true
    gitlab_url            = "https://gitlab.example.com"
    gitlab_project_path   = "prolifel/aws-aft"
    config_bucket_arn     = "arn:aws:s3:::test-config"
    ephp_ou_ids           = ["ou-test-1"]
    sso_target_account_id = "123456789012"
    sso_group_arns = {
      "read-only" = ["arn:aws:identitystore:::group/00000000-0000-4000-8000-000000000000"]
    }
    allowed_log_account_ids    = ["123456789012"]
    guardduty_admin_account_id = "123456789012"
    inspector_admin_account_id = "123456789012"
    macie_admin_account_id     = "123456789012"
  }

  assert {
    condition     = output.gitlab_ci_role_arn == "arn:aws:iam::123456789012:role/test-gitlab-ci"
    error_message = "ci_enabled must create the GitLab CI role on the management plane"
  }
}
```

Add this assert to the existing `account_plane` run:

```hcl
  assert {
    condition     = output.gitlab_ci_role_arn == ""
    error_message = "ci module must be a no-op on the account plane"
  }
```

- [ ] **Step 8: Format and verify**

Run: `tofu fmt`
Expected: no diff output or reformatted files only.

Run: `tofu validate`
Expected: `Success! The configuration is valid.`

Run: `tofu test`
Expected: all runs pass, including `ci_management_plane`.

- [ ] **Step 9: Commit**

```bash
git add modules/ci tests/account_baseline.tftest.hcl variables.tf main.tf outputs.tf
git commit -m "feat: add GitLab CI OIDC module"
```

---

### Task 2: GitLab-native account request YAML in inventory script

**Files:**
- Modify: `scripts/account-inventory.sh` (the `--aft-requests` branch)
- Modify: `tests/inventory_test.sh`

- [ ] **Step 1: Add an SSO name splitter to `scripts/account-inventory.sh`**

Insert before the `MODE` dispatch (after the `row_for_account` helper definition):

```bash
split_sso_name() {
  local name="$1" part="$2"
  if [[ "$name" == *-* ]]; then
    if [[ "$part" == "first" ]]; then
      echo "${name%-*}"
    else
      echo "${name##*-}"
    fi
  else
    if [[ "$part" == "first" ]]; then
      echo "$name"
    else
      echo ""
    fi
  fi
}
```

- [ ] **Step 2: Replace the request-file heredoc in `--aft-requests`**

Replace this block:

```bash
    cat > "$OUT_DIR/$id.yaml" <<EOF
account_request:
  account_name: "$name"
  email: "$email"
  managed_org_unit: "$(ou_name_of "$leaf_ou")"
  account_customizations_name: "aws-hardened"
EOF
```

with:

```bash
    cat > "$OUT_DIR/$id.yaml" <<EOF
account_name: "$name"
email: "$email"
managed_org_unit: "$(ou_name_of "$leaf_ou")"
sso_user_email: "$email"
sso_user_first_name: "$(split_sso_name "$name" first)"
sso_user_last_name: "$(split_sso_name "$name" last)"
account_tags:
  Environment: Dev
customizations: aws-hardened
EOF
```

- [ ] **Step 3: Update `tests/inventory_test.sh` expectations**

Replace:

```bash
grep -q 'account_customizations_name: "aws-hardened"' "$req_dir/222222222222.yaml"
grep -q 'managed_org_unit: "ePHI-A-Prod"' "$req_dir/222222222222.yaml"
grep -q 'managed_org_unit: "ePHI-B"' "$req_dir/333333333333.yaml"
```

with:

```bash
grep -q 'customizations: aws-hardened' "$req_dir/222222222222.yaml"
grep -q 'managed_org_unit: "ePHI-A-Prod"' "$req_dir/222222222222.yaml"
grep -q 'managed_org_unit: "ePHI-B"' "$req_dir/333333333333.yaml"
grep -q 'sso_user_first_name: "App"' "$req_dir/222222222222.yaml"
grep -q 'sso_user_last_name: "A"' "$req_dir/222222222222.yaml"
```

And replace the final `echo "PASS: AFT request files"` with `echo "PASS: account request files"`.

- [ ] **Step 4: Verify**

Run: `bash tests/inventory_test.sh`
Expected: `PASS: account request files` and exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/account-inventory.sh tests/inventory_test.sh
git commit -m "feat: emit GitLab-native account request YAML"
```

---

### Task 3: Account factory and account plane scripts

**Files:**
- Create: `scripts/account-factory.sh`
- Create: `scripts/account-plane.sh`
- Modify: `tests/inventory_test.sh` (append validation check)

- [ ] **Step 1: Create `scripts/account-factory.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
REQ_DIR="${2:-accounts}"
OUT_FILE="${ACCOUNT_IDS_FILE:-account_ids.txt}"
REQUIRED_FIELDS="account_name email managed_org_unit sso_user_email sso_user_first_name sso_user_last_name"

fail() { echo "ERROR: $*" >&2; exit 1; }

field_of() {
  local file="$1" field="$2"
  grep -E "^${field}:" "$file" | head -1 | sed "s/^${field}: *//" | tr -d '"'
}

validate_dir() {
  local dir="$1" file field email found=0
  for file in "$dir"/*.yaml; do
    [[ -f "$file" ]] || continue
    found=1
    for field in $REQUIRED_FIELDS; do
      grep -Eq "^${field}: +.+" "$file" || fail "$file missing required field '$field'"
    done
    email=$(field_of "$file" email)
    [[ "$email" =~ ^[^@]+@[^@]+$ ]] || fail "$file has invalid email '$email'"
  done
  [[ "$found" == 1 ]] || fail "no request files found in $dir"
}

org_account_ids_by_email() {
  aws organizations list-accounts --output json | jq -r '.Accounts[] | "\(.Email)\t\(.Id)"'
}

account_id_by_email() {
  local email="$1"
  org_account_ids_by_email | awk -F '\t' -v e="$email" '$1==e {print $2; exit}'
}

product_id() {
  local name="$1"
  aws servicecatalog search-products-as-admin --output json |
    jq -r --arg name "$name" \
      '.ProductViewDetails[].ProductViewSummary | select(.Name == $name) | .ProductId' |
    head -1
}

provisioned_product_id() {
  local name="$1"
  aws servicecatalog search-provisioned-products --output json |
    jq -r --arg name "$name" '.ProvisionedProducts[] | select(.Name == $name) | .Id' |
    head -1
}

wait_available() {
  local ppid="$1" status
  for _ in $(seq 1 120); do
    status=$(aws servicecatalog describe-provisioned-product --id "$ppid" \
      --query 'ProvisionedProductDetail.Status' --output text)
    [[ "$status" == "AVAILABLE" ]] && return 0
    [[ "$status" == "ERROR" ]] && fail "provisioned product $ppid ended in ERROR"
    sleep 30
  done
  fail "provisioned product $ppid did not become AVAILABLE within 60 minutes"
}

tags_of_file() {
  local file="$1"
  sed -n '/^account_tags:/,/^[^ ]/p' "$file" |
    grep -E '^  .+:' |
    sed -E 's/^  ([^:]+): *"?([^"]*)"?$/\1=\2/'
}

provision() {
  local file="$1" email name ou account_id ppid pid artifact tag_args tkey
  email=$(field_of "$file" email)
  name=$(field_of "$file" account_name)
  ou=$(field_of "$file" managed_org_unit)
  account_id=$(account_id_by_email "$email")
  if [[ -n "$account_id" ]]; then
    echo "SKIP SC: $email already exists as account $account_id" >&2
    echo "$account_id"
    return 0
  fi
  pid=$(product_id "AWS Control Tower Account Factory")
  [[ -n "$pid" ]] || fail "Account Factory product not found"
  artifact=$(aws servicecatalog list-provisioning-artifacts --product-id "$pid" \
    --query 'ProvisioningArtifactDetails[?Status==`AVAILABLE`].Id | [0]' --output text)
  [[ "$artifact" != "None" && -n "$artifact" ]] || fail "no AVAILABLE provisioning artifact for product $pid"
  tag_args=()
  while read -r tkey; do
    [[ -z "$tkey" ]] && continue
    tag_args+=(--tags "Key=${tkey%%=*},Value=${tkey#*=}")
  done < <(tags_of_file "$file")
  ppid=$(provisioned_product_id "$name")
  if [[ -n "$ppid" ]]; then
    aws servicecatalog update-provisioned-product \
      --provisioned-product-id "$ppid" \
      --provisioning-artifact-id "$artifact" \
      --provisioning-parameters Key=ManagedOrganizationalUnit,Value="$ou" >/dev/null
    echo "UPDATE: $name" >&2
  else
    aws servicecatalog provision-product \
      --product-id "$pid" \
      --provisioning-artifact-id "$artifact" \
      --provisioned-product-name "$name" \
      --provisioning-parameters \
        Key=AccountEmail,Value="$email" \
        Key=AccountName,Value="$name" \
        Key=ManagedOrganizationalUnit,Value="$ou" \
        Key=SSOUserEmail,Value="$(field_of "$file" sso_user_email)" \
        Key=SSOUserFirstName,Value="$(field_of "$file" sso_user_first_name)" \
        Key=SSOUserLastName,Value="$(field_of "$file" sso_user_last_name)" \
        Key=SSOUserGroupName,Value="" \
      "${tag_args[@]}" >/dev/null
    echo "CREATE: $name" >&2
  fi
  ppid=$(provisioned_product_id "$name")
  [[ -n "$ppid" ]] || fail "provisioned product $name not found after request"
  wait_available "$ppid"
  for _ in $(seq 1 60); do
    account_id=$(account_id_by_email "$email")
    [[ -n "$account_id" ]] && break
    sleep 30
  done
  [[ -n "$account_id" ]] || fail "account $email not visible in Organizations after provisioning"
  echo "$account_id"
}

terminate_stale() {
  [[ "${ALLOW_TERMINATE:-0}" == "1" ]] || {
    echo "WARN: provisioned products with no matching request file present; set ALLOW_TERMINATE=1 to terminate" >&2
    return 0
  }
  local names="" file ppid name
  for file in "$REQ_DIR"/*.yaml; do
    [[ -f "$file" ]] && names+="$(field_of "$file" account_name)"$'\n'
  done
  while read -r ppid name; do
    [[ -z "$ppid" ]] && continue
    if ! grep -qxF "$name" <<<"$names"; then
      aws servicecatalog terminate-provisioned-product --provisioned-product-id "$ppid" >/dev/null
      echo "TERMINATE: $name" >&2
    fi
  done < <(aws servicecatalog search-provisioned-products --output json |
    jq -r '.ProvisionedProducts[] | "\(.Id)\t\(.Name)"')
}

diff_mode() {
  validate_dir "$REQ_DIR"
  local file email name account_id
  echo "== ACCOUNT FACTORY PLAN =="
  for file in "$REQ_DIR"/*.yaml; do
    [[ -f "$file" ]] || continue
    email=$(field_of "$file" email)
    name=$(field_of "$file" account_name)
    account_id=$(account_id_by_email "$email")
    if [[ -n "$account_id" ]]; then
      echo "skip (exists in org): $name"
    elif [[ -n "$(provisioned_product_id "$name")" ]]; then
      echo "update: $name"
    else
      echo "create: $name"
    fi
  done
  local names=""
  for file in "$REQ_DIR"/*.yaml; do
    [[ -f "$file" ]] && names+="$(field_of "$file" account_name)"$'\n'
  done
  while read -r ppid name; do
    [[ -z "$ppid" ]] && continue
    grep -qxF "$name" <<<"$names" || echo "terminate: $name"
  done < <(aws servicecatalog search-provisioned-products --output json |
    jq -r '.ProvisionedProducts[] | "\(.Id)\t\(.Name)"')
}

case "$MODE" in
  --validate)
    validate_dir "$REQ_DIR"
    echo "PASS: account requests valid"
    ;;
  --diff)
    diff_mode
    ;;
  run)
    validate_dir "$REQ_DIR"
    : > "$OUT_FILE"
    while read -r file; do
      [[ -f "$file" ]] || continue
      echo "$(provision "$file")" >> "$OUT_FILE"
    done < <(ls "$REQ_DIR"/*.yaml 2>/dev/null | sort)
    terminate_stale
    echo "account ids written to $OUT_FILE" >&2
    ;;
  *)
    fail "unknown mode '$MODE'; use --validate, --diff, or run"
    ;;
esac
```

- [ ] **Step 2: Create `scripts/account-plane.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_ID="${1:?usage: account-plane.sh <account-id>}"
DEPLOY_ROLE="${DEPLOY_ROLE_NAME:-hardened-deploy}"
CT_EXEC_ROLE="AWSControlTowerExecution"
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-account-bootstrap}"
PLANE_DIR="${PLANE_DIR:-account-plane}"
SESSION="ci-${CI_PIPELINE_ID:-manual}"

assume_role() {
  aws sts assume-role --role-arn "$1" --role-session-name "$SESSION" --output json
}

use_creds() {
  local json="$1"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  AWS_ACCESS_KEY_ID=$(jq -r .Credentials.AccessKeyId <<<"$json")
  AWS_SECRET_ACCESS_KEY=$(jq -r .Credentials.SecretAccessKey <<<"$json")
  AWS_SESSION_TOKEN=$(jq -r .Credentials.SessionToken <<<"$json")
}

json=$(assume_role "arn:aws:iam::${ACCOUNT_ID}:role/${DEPLOY_ROLE}" 2>/dev/null) ||
  json=""

if [[ -n "$json" ]]; then
  echo "$DEPLOY_ROLE already present in $ACCOUNT_ID" >&2
  use_creds "$json"
else
  echo "bootstrapping $DEPLOY_ROLE in $ACCOUNT_ID via $CT_EXEC_ROLE" >&2
  use_creds "$(assume_role "arn:aws:iam::${ACCOUNT_ID}:role/${CT_EXEC_ROLE}")"
  (
    cd "$BOOTSTRAP_DIR"
    tofu init -backend-config="key=${ACCOUNT_ID}/bootstrap.tfstate"
    tofu apply -auto-approve -var "account_id=${ACCOUNT_ID}"
  )
  use_creds "$(assume_role "arn:aws:iam::${ACCOUNT_ID}:role/${DEPLOY_ROLE}")"
fi

(
  cd "$PLANE_DIR"
  tofu init -backend-config="key=${ACCOUNT_ID}/account-plane.tfstate"
  tofu apply -auto-approve \
    -var "config_bucket_name=${CONFIG_BUCKET_ARN##*:::}"
)
```

- [ ] **Step 3: Append a validation check to `tests/inventory_test.sh`**

After the final `echo "PASS: account request files"`:

```bash
scripts/account-factory.sh --validate "$req_dir"
echo "PASS: account request validation"
```

- [ ] **Step 4: Verify**

Run: `bash -n scripts/account-factory.sh scripts/account-plane.sh`
Expected: exit 0, no output.

Run: `bash tests/inventory_test.sh`
Expected: final line `PASS: account request validation`, exit 0.

- [ ] **Step 5: Commit**

```bash
git add scripts/account-factory.sh scripts/account-plane.sh tests/inventory_test.sh
git commit -m "feat: add GitLab-native account factory and account plane scripts"
```

---

### Task 4: `.gitlab-ci.yml` pipeline template

**Files:**
- Create: `.gitlab-ci.yml`
- Create: `ci/oidc.sh`

- [ ] **Step 1: Create `ci/oidc.sh`**

```sh
#!/usr/bin/env sh
# Sourced by CI jobs. Requires CI_ROLE_ARN variable and id_token OIDC_TOKEN.
creds=$(aws sts assume-role-with-web-identity \
  --role-arn "$CI_ROLE_ARN" \
  --role-session-name "ci-$CI_PIPELINE_ID" \
  --web-identity-token-file "$STS_WEB_IDENTITY_TOKEN_FILE") || exit 1
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
AWS_ACCESS_KEY_ID=$(printf '%s' "$creds" | jq -r .Credentials.AccessKeyId)
AWS_SECRET_ACCESS_KEY=$(printf '%s' "$creds" | jq -r .Credentials.SecretAccessKey)
AWS_SESSION_TOKEN=$(printf '%s' "$creds" | jq -r .Credentials.SessionToken)
```

- [ ] **Step 2: Create `.gitlab-ci.yml`**

```yaml
# Template: copy into the deployment repo (e.g. prolifel/aws-aft) together
# with scripts/ and ci/. Set CI/CD variables:
#   CI_ROLE_ARN       - ARN of the gitlab-ci role created by modules/ci
#   CONFIG_BUCKET_ARN - ARN of the management-plane handoff config bucket

stages:
  - account-factory
  - management-plane
  - account-plane
  - inventory

variables:
  AWS_DEFAULT_REGION: ap-southeast-3

.aws-oidc:
  image: alpine:3.20
  id_tokens:
    OIDC_TOKEN:
      aud: sts.amazonaws.com
  before_script:
    - apk add --no-cache aws-cli jq curl unzip
    - source ci/oidc.sh

.tofu:
  image: alpine:3.20
  id_tokens:
    OIDC_TOKEN:
      aud: sts.amazonaws.com
  before_script:
    - apk add --no-cache aws-cli jq curl unzip
    - source ci/oidc.sh
    - curl -fsSL -o /tmp/tofu.zip https://github.com/opentofu/opentofu/releases/download/v1.8.0/tofu_1.8.0_linux_amd64.zip
    - unzip -o /tmp/tofu.zip -d /usr/local/bin/

provision:
  extends: .aws-oidc
  stage: account-factory
  resource_group: account-factory
  rules:
    - if: '$CI_PIPELINE_SOURCE == "push"'
      changes:
        - accounts/**
  script:
    - scripts/account-factory.sh --validate accounts
    - scripts/account-factory.sh --diff accounts
    - scripts/account-factory.sh accounts
  artifacts:
    paths:
      - account_ids.txt
    expire_in: 1 day

customize:
  extends: .tofu
  stage: account-plane
  needs:
    - provision
  rules:
    - if: '$CI_PIPELINE_SOURCE == "push"'
      changes:
        - accounts/**
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
  script:
    - |
      if [[ ! -f account_ids.txt ]]; then
        scripts/account-inventory.sh --json |
          jq -r '.[] | select(.is_management == false) | .account_id' > account_ids.txt
      fi
      while read -r account_id; do
        [[ -z "$account_id" ]] && continue
        scripts/account-plane.sh "$account_id"
      done < account_ids.txt
  artifacts:
    paths:
      - account_ids.txt
    when: always
    expire_in: 1 day

management-plane:
  extends: .tofu
  stage: management-plane
  rules:
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
    - if: '$CI_PIPELINE_SOURCE == "push"'
      changes:
        - management/**
  script:
    - cd management
    - tofu init
    - tofu apply -auto-approve

inventory:
  extends: .aws-oidc
  stage: inventory
  rules:
    - if: '$CI_PIPELINE_SOURCE == "schedule"'
  script:
    - scripts/account-inventory.sh --inventory
```

- [ ] **Step 3: Verify**

Run: `bash -n ci/oidc.sh`
Expected: exit 0.

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.gitlab-ci.yml')); print('YAML OK')"`
Expected: `YAML OK`. If `yaml` is missing locally, use `ruby -e "require 'yaml'; YAML.load_file('.gitlab-ci.yml'); puts 'YAML OK'"`.

- [ ] **Step 4: Commit**

```bash
git add .gitlab-ci.yml ci/oidc.sh
git commit -m "feat: add GitLab CI pipeline template"
```

---

### Task 5: OIDC ingress configs

**Files:**
- Create: `docs/gitlab-oidc/cloudflared.yml`
- Create: `docs/gitlab-oidc/nginx-proxy-manager.conf`
- Create: `docs/gitlab-oidc/README.md`

- [ ] **Step 1: Create `docs/gitlab-oidc/cloudflared.yml`**

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

- [ ] **Step 2: Create `docs/gitlab-oidc/nginx-proxy-manager.conf`**

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

- [ ] **Step 3: Create `docs/gitlab-oidc/README.md`**

~~~markdown
# GitLab OIDC ingress

AWS fetches the OIDC discovery document and JWKS at assume-role time, so only
two paths need to be public: `/.well-known/*` and `/oauth/discovery/keys`.
Everything else returns 404.

## Setup

1. DNS: point `gitlab.example.com` at Cloudflare; tunnel through the
   `cloudflared` config in this directory. Adjust the `gitlab.example.com`
   hostname and the `<TUNNEL_ID>` placeholder.
2. Nginx Proxy Manager: create a proxy host `gitlab.example.com` with the two
   custom locations from `nginx-proxy-manager.conf` (or import the conf
   directly). Enable websockets. Keep "Block common exploits" off — the
   tunnel already path-filters, and the exploit rules can break OIDC JSON
   responses. Internally, GitLab listens on plain HTTP at `gitlab:80`.
3. GitLab (`gitlab.rb`): set `external_url 'https://gitlab.example.com'` so
   the discovery document advertises the public issuer and `jwks_uri`.
   Reconfigure: `sudo gitlab-ctl reconfigure`.
4. Verify:

   `curl -fsS https://gitlab.example.com/.well-known/openid-configuration`
   `curl -fsS https://gitlab.example.com/oauth/discovery/keys`

   Both return GitLab JSON. Any other path must return 404.

## Thumbprint fallback

`modules/ci` leaves `thumbprint_list` empty so AWS auto-fetches the cert.
If AWS rejects the provider (rare with Cloudflare's public CA), capture the
SHA-1 thumbprint and pass it as `oidc_thumbprint`:

```sh
echo | openssl s_client -connect gitlab.example.com:443 -servername gitlab.example.com 2>/dev/null |
  openssl x509 -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':' | tr 'A-F' 'a-f'
```
~~~

- [ ] **Step 4: Commit**

```bash
git add docs/gitlab-oidc
git commit -m "docs: add GitLab OIDC ingress configs"
```

---

### Task 6: GitLab deployment runbook + AFT removal

**Files:**
- Create: `docs/gitlab-deployment.md`
- Delete: `docs/aft-deployment.md`
- Delete: `aft/main.tf`, `aft/variables.tf`, `aft/aft-sandbox/main.tf`

- [ ] **Step 1: Create `docs/gitlab-deployment.md`**

~~~markdown
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
```

Set `CI_ROLE_ARN` and `CONFIG_BUCKET_ARN` as GitLab CI/CD variables.

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
~~~

- [ ] **Step 2: Remove the old AFT runbook and scaffold**

```bash
git rm docs/aft-deployment.md
git rm -r aft
```

`aft/terraform.tfvars` is gitignored and stays untracked on disk; remove the
whole `aft/` directory locally when done.

- [ ] **Step 3: Verify**

Run: `git status --short`
Expected: deletions staged, no other changes.

- [ ] **Step 4: Commit**

```bash
git commit -m "docs: replace AFT runbook with GitLab-native runbook"
git commit -m "chore: remove AFT scaffold"
```

---

### Task 7: Final verification

**Files:** none (verification only)

- [ ] **Step 1: Format and validate**

Run: `tofu fmt`
Expected: no output.

Run: `tofu validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 2: Test suite**

Run: `tofu test`
Expected: all runs pass.

Run: `bash tests/inventory_test.sh`
Expected: exit 0 with `PASS:` lines.

Run: `bash -n scripts/account-factory.sh scripts/account-plane.sh ci/oidc.sh`
Expected: exit 0.

- [ ] **Step 3: Self-review against the spec**

- `modules/ci/` OIDC provider + role: Task 1.
- `.gitlab-ci.yml` template: Task 4.
- cloudflared + NPM configs: Task 5.
- `docs/gitlab-deployment.md` replaces `docs/aft-deployment.md`: Task 6.
- Inventory `--aft-requests` new format: Task 2.
- `aft/` removed: Task 6.
- `hardened-deploy` bootstrap + config handoff: Task 3 + Task 6 runbook.

- [ ] **Step 4: Leave the working tree clean**

Run: `git status --short`
Expected: empty output after the final commit.
