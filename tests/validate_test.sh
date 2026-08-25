#!/usr/bin/env bash
# Deterministic unit test for validate-accounts.sh pure logic.
# Run locally: bash tests/validate_test.sh (no AWS required).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$tmp/valid" "$tmp/invalid" "$tmp/missing"

cat > "$tmp/valid/ok.yaml" <<'YAML'
account_name: app-prod
email: app-prod@example.com
managed_org_unit: Workloads
owner: platform
environment: prod
cost_center: CC1
regions:
  - ap-southeast-3
tags:
  Environment: prod
YAML

cat > "$tmp/invalid/bad.yaml" <<'YAML'
account_name: app-dev
email: not-an-email
managed_org_unit: Workloads
owner: platform
environment: nope
cost_center: CC2
regions: ap-southeast-3
tags: {}
YAML

cat > "$tmp/missing/missing.yaml" <<'YAML'
account_name: app-test
email: app-test@example.com
YAML

# Valid request passes and reports valid.
VALIDATE_ACCOUNTS_REQUIRE_AWS=0 VALIDATION_REPORT_PATH="$tmp/valid/validation.json" \
  bash "$ROOT/scripts/validate-accounts.sh" "$tmp/valid" >/dev/null 2>&1 \
  && grep -q '"status": "valid"' "$tmp/valid/validation.json" \
  || fail "valid request should pass"

# Invalid request fails with invalid report.
if VALIDATE_ACCOUNTS_REQUIRE_AWS=0 VALIDATION_REPORT_PATH="$tmp/invalid/validation.json" \
   bash "$ROOT/scripts/validate-accounts.sh" "$tmp/invalid" >/dev/null 2>&1; then
  fail "invalid request should fail validation"
fi
grep -q '"status": "invalid"' "$tmp/invalid/validation.json" || fail "expected invalid report"

# Missing-field request fails with a missing-field error.
if VALIDATE_ACCOUNTS_REQUIRE_AWS=0 VALIDATION_REPORT_PATH="$tmp/missing/validation.json" \
   bash "$ROOT/scripts/validate-accounts.sh" "$tmp/missing" >/dev/null 2>&1; then
  fail "missing-field request should fail validation"
fi
grep -q "missing_required_field" "$tmp/missing/validation.json" || fail "expected missing-field error"

echo "PASS: validate account tests"
