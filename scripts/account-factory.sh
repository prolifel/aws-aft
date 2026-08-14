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
  local file email name account_id names ppid
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
  names=""
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
