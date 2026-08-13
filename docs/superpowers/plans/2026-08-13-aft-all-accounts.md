# AFT All-Accounts Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an account inventory tool and an AFT deployment runbook so the aws-hardened module runs in every existing account and every new Control Tower account.

**Architecture:** Two planes. Management plane runs the module with `management_account = true` as a standalone root in the org management account (SCPs, SSO, org CloudTrail, org enablement). Account plane runs the module with `management_account = false` via AFT account customizations in every member account, reading a handoff `config.json` from a small config bucket. A Bash script inventories the org (account -> OU -> inherited SCPs) and can emit AFT account-request files for backfill.

**Tech Stack:** Bash, `aws` CLI, `jq`, OpenTofu (>= 1.8.0), AFT (Account Factory for Terraform).

**Spec:** `docs/superpowers/specs/2026-08-12-aft-all-accounts-design.md`

---

## File Structure

- Create: `scripts/account-inventory.sh` — org inventory (CSV/JSON), AFT account-request generation. Sole code artifact.
- Create: `tests/fixtures/aws` — fake `aws` CLI returning canned Organizations data, installed on PATH by the test.
- Create: `tests/inventory_test.sh` — runnable check (no framework) asserting CSV rows, JSON output, and request files against the fixture.
- Create: `docs/aft-deployment.md` — runbook: AFT bootstrap in the dedicated AFT management account, management-plane root, account customizations, backfill, verification.

## Fixture Organization (used by every task)

Root `r-abc`. OUs: `ou-111` "ePHI-A", `ou-222` "ePHI-B", `ou-333` "ePHI-A-Prod" (child of `ou-111`). SCPs attached:

| Target | SCPs |
|---|---|
| `r-abc` (root) | `DenyIAMUserCreations`, `RequireMFA` |
| `ou-111` | `DenyUnencryptedResources` |
| `ou-333` | `DenyPublicAdminPorts` |
| `ou-222` | `DenyInlineUserPolicies` |

Accounts:

| ID | Name | Email | Parent |
|---|---|---|---|
| `111111111111` | Management | mgmt@example.com | `r-abc` |
| `222222222222` | App-A | app-a@example.com | `ou-333` |
| `333333333333` | App-B | app-b@example.com | `ou-222` |

Expected inheritance (SCPs accumulate root -> leaf):

- Management: path `/`, scps `DenyIAMUserCreations,RequireMFA`, management_account=true
- App-A: path `/ePHI-A/ePHI-A-Prod`, scps `DenyIAMUserCreations,DenyPublicAdminPorts,DenyUnencryptedResources,RequireMFA`, management_account=false
- App-B: path `/ePHI-B`, scps `DenyIAMUserCreations,DenyInlineUserPolicies,RequireMFA`, management_account=false

---

### Task 1: Fixture shim + failing CSV test

**Files:**
- Create: `tests/fixtures/aws`
- Create: `tests/inventory_test.sh`

- [ ] **Step 1: Write the fake `aws` CLI**

`tests/fixtures/aws` (executable):

```bash
#!/usr/bin/env bash
set -euo pipefail

cmd="$1"
sub="$2"
shift 2

id_of() {
  local prev="" id=""
  for a in "$@"; do
    if [[ "$prev" == "--child-id" || "$prev" == "--target-id" || "$prev" == "--parent-id" ]]; then id="$a"; fi
    prev="$a"
  done
  printf '%s' "$id"
}

case "$cmd $sub" in
  "organizations describe-organization")
    cat <<'EOF'
{"Organization":{"ManagementAccountId":"111111111111"}}
EOF
    ;;
  "organizations list-accounts")
    cat <<'EOF'
{"Accounts":[
  {"Id":"111111111111","Name":"Management","Email":"mgmt@example.com","Status":"ACTIVE"},
  {"Id":"222222222222","Name":"App-A","Email":"app-a@example.com","Status":"ACTIVE"},
  {"Id":"333333333333","Name":"App-B","Email":"app-b@example.com","Status":"ACTIVE"}
]}
EOF
    ;;
  "organizations list-roots")
    cat <<'EOF'
{"Roots":[{"Id":"r-abc","Name":"Root"}]}
EOF
    ;;
  "organizations list-organizational-units-for-parent")
    case "$(id_of "$@")" in
      "r-abc") cat <<'EOF'
{"OrganizationalUnits":[{"Id":"ou-111","Name":"ePHI-A"},{"Id":"ou-222","Name":"ePHI-B"}]}
EOF
        ;;
      "ou-111") cat <<'EOF'
{"OrganizationalUnits":[{"Id":"ou-333","Name":"ePHI-A-Prod"}]}
EOF
        ;;
      *) cat <<'EOF'
{"OrganizationalUnits":[]}
EOF
        ;;
    esac
    ;;
  "organizations list-parents")
    case "$(id_of "$@")" in
      "111111111111"|"ou-111"|"ou-222") printf '%s\n' '{"Parents":[{"Id":"r-abc"}]}';;
      "222222222222") printf '%s\n' '{"Parents":[{"Id":"ou-333"}]}';;
      "ou-333") printf '%s\n' '{"Parents":[{"Id":"ou-111"}]}';;
      "333333333333") printf '%s\n' '{"Parents":[{"Id":"ou-222"}]}';;
      *) printf '%s\n' '{"Parents":[]}';;
    esac
    ;;
  "organizations list-policies-for-target")
    case "$(id_of "$@")" in
      "r-abc") printf '%s\n' '{"Policies":[{"Name":"DenyIAMUserCreations"},{"Name":"RequireMFA"}]}';;
      "ou-111") printf '%s\n' '{"Policies":[{"Name":"DenyUnencryptedResources"}]}';;
      "ou-333") printf '%s\n' '{"Policies":[{"Name":"DenyPublicAdminPorts"}]}';;
      "ou-222") printf '%s\n' '{"Policies":[{"Name":"DenyInlineUserPolicies"}]}';;
      *) printf '%s\n' '{"Policies":[]}';;
    esac
    ;;
  *) echo "unhandled aws call: $cmd $sub $*" >&2; exit 1 ;;
esac
```

Note: `list-parents` for `ou-111`/`ou-222` returns the root; for `222222222222` returns `ou-333` (leaf of App-A).

- [ ] **Step 2: Write the failing CSV test**

`tests/inventory_test.sh` (executable):

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export PATH="$PWD/tests/fixtures:$PATH"

out=$(scripts/account-inventory.sh --inventory)

assert_row() {
  local account="$1" expected="$2"
  if ! grep -F "$expected" <<<"$out" >/dev/null; then
    echo "FAIL: missing row for $account" >&2
    echo "expected substring: $expected" >&2
    echo "--- output ---" >&2
    echo "$out" >&2
    exit 1
  fi
}

assert_row Management "111111111111,Management,mgmt@example.com,ACTIVE,/,r-abc,true,DenyIAMUserCreations;RequireMFA"
assert_row App-A "222222222222,App-A,app-a@example.com,ACTIVE,/ePHI-A/ePHI-A-Prod,ou-333,false,DenyIAMUserCreations;DenyPublicAdminPorts;DenyUnencryptedResources;RequireMFA"
assert_row App-B "333333333333,App-B,app-b@example.com,ACTIVE,/ePHI-B,ou-222,false,DenyIAMUserCreations;DenyInlineUserPolicies;RequireMFA"

echo "PASS: inventory CSV"
```

- [ ] **Step 3: Run the test, verify it fails**

Run: `bash tests/inventory_test.sh`
Expected: FAIL — `scripts/account-inventory.sh: No such file or directory`.

- [ ] **Step 4: Commit the failing test**

```bash
git add tests/fixtures/aws tests/inventory_test.sh
git commit -m "test: inventory CSV expectations against Organizations fixture"
```

---

### Task 2: Implement CSV inventory

**Files:**
- Create: `scripts/account-inventory.sh`

- [ ] **Step 1: Write the script (CSV mode)**

`scripts/account-inventory.sh` (executable):

```bash
#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---inventory}"

org_json=$(aws organizations describe-organization --output json)
mgmt_id=$(jq -r '.Organization.ManagementAccountId // .Organization.MasterAccountId' <<<"$org_json")
root_id=$(aws organizations list-roots --output json | jq -r '.Roots[0].Id')

ou_name_rows=""
collect_ou() {
  local parent="$1" id name
  while read -r id name; do
    [[ -z "$id" ]] && continue
    ou_name_rows+="$id $name"$'\n'
    collect_ou "$id"
  done < <(aws organizations list-organizational-units-for-parent --parent-id "$parent" --output json |
    jq -r '.OrganizationalUnits[] | "\(.Id) \(.Name)"')
}
collect_ou "$root_id"

ou_name_of() {
  local id="$1"
  awk -v id="$id" '$1==id {$1=""; sub(/^ /, ""); print}' <<<"$ou_name_rows"
}

parent_of() {
  aws organizations list-parents --child-id "$1" --output json | jq -r '.Parents[0].Id // ""'
}

scps_of() {
  aws organizations list-policies-for-target --target-id "$1" --filter SCP --output json |
    jq -r '.Policies[].Name' | sort
}

row_for_account() {
  local id="$1" name="$2" email="$3" status="$4"
  local node="" parent="" path_str="" scps_str="" features
  local -a chain=() scps=()
  node="$(parent_of "$id")"
  while [[ -n "$node" ]]; do
    chain+=("$node")
    while IFS= read -r s; do [[ -n "$s" ]] && scps+=("$s"); done < <(scps_of "$node")
    [[ "$node" == "$root_id" ]] && break
    node="$(parent_of "$node")"
  done

  local -a path_parts=() n
  local i
  for ((i=${#chain[@]}-1; i>=0; i--)); do
    n="${chain[$i]}"
    [[ "$n" == "$root_id" ]] && continue
    path_parts+=("$(ou_name_of "$n")")
  done
  if [[ ${#path_parts[@]} -eq 0 ]]; then
    path_str="/"
  else
    path_str="/$(IFS=/; printf '%s' "${path_parts[*]}")"
  fi

  scps_str="$(printf '%s\n' ${scps[@]+"${scps[@]}"} | sort | paste -sd';' -)"

  if [[ "$id" == "$mgmt_id" ]]; then
    features="management_account=true;identity=true;scp=true;audit=true;encryption=true;detection=true"
  else
    features="management_account=false;identity=true;scp=true;audit=true;encryption=true;detection=true"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$id" "$name" "$email" "$status" "$path_str" \
    "${chain[0]}" "$([[ "$id" == "$mgmt_id" ]] && echo true || echo false)" \
    "$scps_str" "$features"
}

echo "account_id,account_name,email,status,ou_path,ou_id,is_management,scps,features"
while read -r id name email status; do
  [[ -z "$id" ]] && continue
  row_for_account "$id" "$name" "$email" "$status"
done < <(aws organizations list-accounts --output json |
  jq -r '.Accounts[] | "\(.Id) \(.Name) \(.Email) \(.Status)"')
```

Column order: `account_id,account_name,email,status,ou_path,ou_id,is_management,scps,features` — matches the test's expected substrings (note `ou_id` is `chain[-1]`, the leaf OU/root).

- [ ] **Step 2: Run the test, verify it passes**

Run: `bash tests/inventory_test.sh`
Expected: `PASS: inventory CSV` — all three row assertions match, with SCPs in alphabetical order and `ou_path` correct.

- [ ] **Step 3: Syntax-check and commit**

```bash
bash -n scripts/account-inventory.sh
git add scripts/account-inventory.sh
git commit -m "feat: account inventory with OU path and inherited SCPs"
```

---

### Task 3: JSON mode

**Files:**
- Modify: `scripts/account-inventory.sh`
- Modify: `tests/inventory_test.sh`

- [ ] **Step 1: Add `--json` mode**

Change the tail of `scripts/account-inventory.sh` from the `echo "account_id,..."` block through the final `done` to:

```bash
header="account_id,account_name,email,status,ou_path,ou_id,is_management,scps,features"
rows=()
while read -r id name email status; do
  [[ -z "$id" ]] && continue
  rows+=("$(row_for_account "$id" "$name" "$email" "$status")")
done < <(aws organizations list-accounts --output json |
  jq -r '.Accounts[] | "\(.Id) \(.Name) \(.Email) \(.Status)"')

if [[ "$MODE" == "--json" ]]; then
  printf '%s\n' "${rows[@]}" | jq -Rr 'split(",") | {
    account_id: .[0], account_name: .[1], email: .[2], status: .[3],
    ou_path: .[4], ou_id: .[5], is_management: (.[6] == "true"),
    scps: (.[7] | split(";")), features: .[8]
  }' | jq -s .
else
  printf '%s\n' "$header"
  printf '%s\n' "${rows[@]}"
fi
```

- [ ] **Step 2: Extend the test with a JSON assertion**

Append to `tests/inventory_test.sh` before the final `echo "PASS: inventory CSV"`:

```bash
json=$(scripts/account-inventory.sh --json)

if ! jq -e '.[] | select(.account_id == "222222222222")
    | .ou_path == "/ePHI-A/ePHI-A-Prod" and .is_management == false
    and (.scps | sort) == (["DenyIAMUserCreations","DenyPublicAdminPorts","DenyUnencryptedResources","RequireMFA"] | sort)' <<<"$json" >/dev/null; then
  echo "FAIL: JSON mode wrong for App-A" >&2
  echo "$json" >&2
  exit 1
fi

echo "PASS: inventory CSV"
echo "PASS: inventory JSON"
```

- [ ] **Step 3: Run the test, verify it passes**

Run: `bash tests/inventory_test.sh`
Expected: `PASS: inventory CSV` and `PASS: inventory JSON`.

- [ ] **Step 4: Commit**

```bash
bash -n scripts/account-inventory.sh
git add scripts/account-inventory.sh tests/inventory_test.sh
git commit -m "feat: JSON inventory mode"
```

---

### Task 4: AFT account-request generation

**Files:**
- Modify: `scripts/account-inventory.sh`
- Modify: `tests/inventory_test.sh`

- [ ] **Step 1: Add `--aft-requests` mode**

Add at the top of `scripts/account-inventory.sh`, after `MODE=`:

```bash
OUT_DIR="${2:-account_request}"
```

Replace the final `if [[ "$MODE" == "--json" ]] ... fi` block with:

```bash
if [[ "$MODE" == "--json" ]]; then
  printf '%s\n' "${rows[@]}" | jq -Rr 'split(",") | {
    account_id: .[0], account_name: .[1], email: .[2], status: .[3],
    ou_path: .[4], ou_id: .[5], is_management: (.[6] == "true"),
    scps: (.[7] | split(";")), features: .[8]
  }' | jq -s .
elif [[ "$MODE" == "--aft-requests" ]]; then
  mkdir -p "$OUT_DIR"
  while read -r id name email status; do
    [[ -z "$id" ]] && continue
    row_for_account "$id" "$name" "$email" "$status" >/dev/null
    if [[ "$id" == "$mgmt_id" ]]; then continue; fi
    leaf_ou="$(parent_of "$id")"
    if [[ "$leaf_ou" == "$root_id" ]]; then
      echo "WARN: $id ($name) sits at root, not in an OU; no request file emitted" >&2
      continue
    fi
    cat > "$OUT_DIR/$id.yaml" <<EOF
account_request:
  account_name: "$name"
  email: "$email"
  managed_org_unit: "$(ou_name_of "$leaf_ou")"
  account_customizations_name: "aws-hardened"
EOF
  done < <(aws organizations list-accounts --output json |
    jq -r '.Accounts[] | "\(.Id) \(.Name) \(.Email) \(.Status)"')
else
  printf '%s\n' "$header"
  printf '%s\n' "${rows[@]}"
fi
```

- [ ] **Step 2: Extend the test with an AFT-requests assertion**

Append to `tests/inventory_test.sh`:

```bash
req_dir=$(mktemp -d)
trap 'rm -rf "$req_dir"' EXIT
scripts/account-inventory.sh --aft-requests "$req_dir" >/dev/null

if [[ ! -f "$req_dir/222222222222.yaml" || ! -f "$req_dir/333333333333.yaml" ]]; then
  echo "FAIL: missing request files" >&2
  exit 1
fi
if [[ -f "$req_dir/111111111111.yaml" ]]; then
  echo "FAIL: request file emitted for management account" >&2
  exit 1
fi
grep -q 'account_customizations_name: "aws-hardened"' "$req_dir/222222222222.yaml"
grep -q 'managed_org_unit: "ePHI-A-Prod"' "$req_dir/222222222222.yaml"
grep -q 'managed_org_unit: "ePHI-B"' "$req_dir/333333333333.yaml"

echo "PASS: inventory CSV"
echo "PASS: inventory JSON"
echo "PASS: AFT request files"
```

- [ ] **Step 3: Run the test, verify it passes**

Run: `bash tests/inventory_test.sh`
Expected: all three `PASS` lines, no warnings on stderr.

- [ ] **Step 4: Commit**

```bash
bash -n scripts/account-inventory.sh
git add scripts/account-inventory.sh tests/inventory_test.sh
git commit -m "feat: generate AFT account request files for existing accounts"
```

---

### Task 5: Deployment runbook

**Files:**
- Create: `docs/aft-deployment.md`

- [ ] **Step 1: Write the runbook**

`docs/aft-deployment.md`:

```markdown
# Deploying to every account via AFT

Architecture summary: the module's management plane runs standalone in the org
management account; the account plane runs via AFT account customizations in
every member account. See the design spec
`docs/superpowers/specs/2026-08-12-aft-all-accounts-design.md` for rationale.

## Prerequisites

- AWS Control Tower landing zone (AFT requires it).
- A dedicated AFT management account (a normal org account; it does not need
  org management permissions).
- OpenTofu >= 1.8.0, `aws` CLI, `jq`.

## 1. Bootstrap AFT in the dedicated account

Follow the official AFT getting-started flow (`aws-aft-core`), deployed into
the AFT management account:

- Pick a home region and set the Terraform version to `1.8.x` or newer — the
  module requires `>= 1.8.0` (`versions.tf`).
- After bootstrap, the AFT account customizations repo is created. You commit
  account customizations there; AFT runs them in each target account.

## 2. Management plane (org management account)

Create a root that calls the module with `management_account = true`, plus a
handoff config bucket. Example `main.tf`:

```hcl
data "aws_organizations_organization" "org" {}

data "aws_caller_identity" "current" {}

variable "region" {
  default = "ap-southeast-3"
}

module "hardened" {
  source = "git::https://github.com/example/aws-hardened.git?ref=v1.0.0"

  management_account = true
  name_prefix        = "prod"
  region             = "ap-southeast-3"
  tags               = { Environment = "production" }

  ephp_ou_ids                   = ["ou-aaaa", "ou-bbbb"]  # your ePHI OU IDs (SCP targets)
  break_glass_role_arn          = "arn:aws:iam::111111111111:role/break-glass"
  config_delegated_admin_account_id = "444444444444"
  guardduty_admin_account_id        = "444444444444"
  inspector_admin_account_id        = "444444444444"
  macie_admin_account_id            = "444444444444"
}

resource "aws_s3_bucket" "config" {
  bucket        = "aws-hardened-config-${data.aws_caller_identity.current.account_id}-${var.region}"
  force_destroy = false
}

resource "aws_s3_bucket_policy" "config" {
  bucket = aws_s3_bucket.config.id
  policy = data.aws_iam_policy_document.config.json
}

data "aws_iam_policy_document" "config" {
  statement {
    effect = "Allow"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.config.arn}/*"]
    principals {
      type        = "AWS"
      identifiers = [for a in data.aws_organizations_organization.org.accounts : "arn:aws:iam::${a.id}:root"]
    }
  }
}

resource "aws_s3_object" "config" {
  bucket  = aws_s3_bucket.config.id
  key     = "config.json"
  content = jsonencode({
    log_bucket_name  = module.hardened.log_bucket_id
    log_bucket_arn   = module.hardened.log_bucket_arn
    config_delegated_admin_account_id = "444444444444"
    guardduty_admin_account_id        = "444444444444"
    inspector_admin_account_id        = "444444444444"
    macie_admin_account_id            = "444444444444"
  })
}
```

Adjust `ephp_ou_ids` (SCP targets), the delegated admin IDs, and the module
`ref`. Run `tofu init && tofu plan && tofu apply`.

## 3. Account customizations (AFT repo)

In the AFT account customizations repo, create the folder
`account-customizations/aws-hardened/terraform/` (the folder name must match
the `account_customizations_name` value used in account requests). Add
`main.tf`:

```hcl
data "aws_s3_object" "config" {
  bucket = "aws-hardened-config-111111111111-ap-southeast-3" # must match the management-plane bucket
  key    = "config.json"
}

locals {
  config = jsondecode(data.aws_s3_object.config.body)
}

module "hardened" {
  source = "git::https://github.com/example/aws-hardened.git?ref=v1.0.0"

  management_account = false
  name_prefix        = "prod"
  region             = "<region>"
  tags               = { Environment = "production" }

  log_bucket_name   = local.config.log_bucket_name
  log_bucket_arn    = local.config.log_bucket_arn
}
```

Commit and push. The AFT pipeline runs this in every account that references
`account_customizations_name: aws-hardened`.

## 4. Backfill existing accounts

```sh
scripts/account-inventory.sh --inventory        # see the full account/OU/SCP matrix
scripts/account-inventory.sh --aft-requests <dir>  # write request files
```

Copy the generated `<account_id>.yaml` files into the AFT repo
`account_request/` directory, commit, and push. AFT runs the account
customizations for each account. Accounts sitting directly at the root are
skipped with a warning — move them into an OU first.

If your AFT version's request schema differs (extra required fields such as
SSO fields), update the generated files accordingly; AFT rejects requests with
invalid fields and reports them via its SNS topic.

## 5. New accounts

Include `account_customizations_name: aws-hardened` in the Account Factory
request. AFT runs the account customizations automatically after provisioning.

## 6. Verify

```sh
scripts/account-inventory.sh --inventory   # confirm every account shows the expected SCPs
bash tests/inventory_test.sh               # local check, no AWS calls
tofu test                                  # module smoke suite unchanged
```

## Operations notes

- The inventory tool is read-only; the `--aft-requests` mode only writes local
  YAML files.
- The log bucket uses Object Lock `COMPLIANCE` (default 6 years): log objects
  are immutable and the bucket cannot be deleted until retention expires.
- SSO permission-set assignment targets a single account
  (`sso_target_account_id`); assigning to every account needs a wrapper around
  the module (out of scope).
- The provider is pinned at `6.58.0` (`versions.tf`); bump deliberately and
  re-run `tofu validate`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/aft-deployment.md
git commit -m "docs: AFT all-accounts deployment runbook"
```

---

### Task 6: Full verification

- [ ] **Step 1: Run the inventory check**

Run: `bash tests/inventory_test.sh`
Expected: three `PASS` lines.

- [ ] **Step 2: Run the module test suite (unchanged code must stay green)**

Run: `tofu test`
Expected: existing smoke tests pass (no module resources changed by this plan).

- [ ] **Step 3: Confirm format and syntax**

```bash
bash -n scripts/account-inventory.sh
git status --short
```

Expected: no syntax errors; only committed files, nothing untracked.

- [ ] **Step 4: Final commit if anything remained**

```bash
git add -A
git commit -m "chore: finalize AFT all-accounts tooling" || true
```
