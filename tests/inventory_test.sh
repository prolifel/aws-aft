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
grep -q 'customizations: aws-hardened' "$req_dir/222222222222.yaml"
grep -q 'managed_org_unit: "ePHI-A-Prod"' "$req_dir/222222222222.yaml"
grep -q 'managed_org_unit: "ePHI-B"' "$req_dir/333333333333.yaml"
grep -q 'sso_user_first_name: "App"' "$req_dir/222222222222.yaml"
grep -q 'sso_user_last_name: "A"' "$req_dir/222222222222.yaml"

echo "PASS: inventory CSV"
echo "PASS: inventory JSON"
echo "PASS: account request files"
