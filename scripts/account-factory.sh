#!/usr/bin/env bash
# Vendor accounts idempotently from account request YAML via Control Tower Account Factory.
# Never re-vends an existing account (matched by email). Writes a JSON status report.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQUEST_DIR="${1:-02-accounts-creation}"
REPORT_DIR="${ACCOUNT_STATUS_DIR:-account-reports}"
REPORT_PATH="$REPORT_DIR/account-factory.json"
STATE_BUCKET="${STATE_BUCKET:?STATE_BUCKET is required}"
STATE_REGION="${STATE_REGION:-ap-southeast-3}"
PRODUCT_ID="${ACCOUNT_FACTORY_PRODUCT_ID:-}"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
[[ -n "$PRODUCT_ID" ]] || { echo "ERROR: ACCOUNT_FACTORY_PRODUCT_ID is required" >&2; exit 2; }

mkdir -p "$REPORT_DIR"
mapfile -t files < <(find "$REQUEST_DIR" -maxdepth 1 -name '*.yaml' ! -name '.ignored-accounts.yaml' | sort)
if [[ ${#files[@]} -eq 0 ]]; then
  printf '[]\n' > "$REPORT_PATH"
  echo "no request files"
  exit 0
fi

declare -A existing
while IFS= read -r email; do
  [[ -z "$email" ]] && continue
  existing[$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]')]=1
done < <(aws organizations list-accounts --output json 2>/dev/null | jq -r '.Accounts[].Email')

: > "$REPORT_PATH"
failed=0
for file in "${files[@]}"; do
  name=$(yq -r .account_name "$file" 2>/dev/null || true)
  email=$(yq -r .email "$file" 2>/dev/null || true)
  ou=$(yq -r .managed_org_unit "$file" 2>/dev/null || true)
  if [[ -z "$name" || -z "$email" || -z "$ou" ]]; then
    echo "invalid request $file" >&2
    printf '{"account_name":"%s","email":"%s","action":"invalid"}\n' "$name" "$email" >> "$REPORT_PATH"
    failed=1
    continue
  fi
  lower=$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]')

  if [[ -n "${existing[$lower]:-}" ]]; then
    msg=$(printf '{"account_name":"%s","email":"%s","action":"skipped-existing"}' "$name" "$email")
  else
    key="account-vending/$name/terraform.tfstate"
    echo "vending $name"
    if (cd "$ROOT/pipeline/account-vending" && tofu init -input=false \
          -backend-config="bucket=$STATE_BUCKET" \
          -backend-config="key=$key" \
          -backend-config="region=$STATE_REGION" >/dev/null \
        && tofu apply -auto-approve -input=false \
          -var="account_name=$name" \
          -var="email=$email" \
          -var="managed_org_unit=$ou" \
          -var="account_factory_product_id=$PRODUCT_ID" >/dev/null); then
      vended=$(aws organizations list-accounts --output json 2>/dev/null \
        | jq -r --arg e "$lower" '.Accounts[] | select((.Email|ascii_downcase)==$e) | .Id' | head -1)
      msg=$(printf '{"account_name":"%s","email":"%s","action":"vended","account_id":"%s"}' "$name" "$email" "${vended:-unknown}")
    else
      msg=$(printf '{"account_name":"%s","email":"%s","action":"failed"}' "$name" "$email")
      failed=1
    fi
  fi
  printf '%s\n' "$msg" >> "$REPORT_PATH"
done
[[ "$failed" -eq 0 ]] || { echo "one or more accounts failed to vendor" >&2; exit 1; }
cat "$REPORT_PATH"
