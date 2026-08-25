#!/usr/bin/env bash
# Apply the mandatory baseline to vended accounts. Reruns reconcile only failed items.
# Bootstrap failures emit a JSON report and exit non-zero; never re-vends.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPORT_DIR="${BOOTSTRAP_REPORT_DIR:-account-reports}"
STATE_BUCKET="${STATE_BUCKET:?STATE_BUCKET is required}"
STATE_REGION="${STATE_REGION:-ap-southeast-3}"
TFVARS="$ROOT/pipeline/account-bootstrap/base.tfvars"
REPORT_PATH="$REPORT_DIR/bootstrap.json"

command -v yq >/dev/null 2>&1 || { echo "ERROR: yq is required" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 2; }
mkdir -p "$REPORT_DIR"
any_failed=0
: > "$REPORT_PATH"

for file in "$ROOT"/02-accounts-creation/*.yaml; do
  [[ -e "$file" ]] || continue
  name=$(yq -r .account_name "$file" 2>/dev/null || true)
  email=$(yq -r .email "$file" 2>/dev/null || true)
  [[ -z "$name" || -z "$email" ]] && continue
  lower=$(printf '%s' "$email" | tr '[:upper:]' '[:lower:]')
  account_id=$(aws organizations list-accounts --output json 2>/dev/null \
    | jq -r --arg e "$lower" '.Accounts[] | select((.Email|ascii_downcase)==$e) | .Id' | head -1)
  if [[ -z "$account_id" ]]; then
    echo "skip $name (not yet vended)"
    continue
  fi
  key="account-bootstrap/$name/terraform.tfstate"
  per="$REPORT_DIR/bootstrap-$name.json"
  if (cd "$ROOT/pipeline/account-bootstrap" && tofu init -input=false \
        -backend-config="bucket=$STATE_BUCKET" \
        -backend-config="key=$key" \
        -backend-config="region=$STATE_REGION" >/dev/null \
      && tofu apply -auto-approve -input=false -var-file="$TFVARS" >/dev/null); then
    printf '{"account_name":"%s","account_id":"%s","status":"completed"}\n' "$name" "$account_id" | tee "$per"
  else
    any_failed=1
    printf '{"account_name":"%s","account_id":"%s","status":"completed-with-bootstrap-failures","bootstrap":[{"resource":"apply","error":"tofu apply failed; inspect logs","retryable":true}]}\n' "$name" "$account_id" | tee "$per"
  fi
  cat "$per" >> "$REPORT_PATH"
done
[[ "$any_failed" -eq 0 ]] || { echo "bootstrap failures; see $REPORT_DIR" >&2; exit 1; }
