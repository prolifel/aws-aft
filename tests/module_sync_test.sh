#!/usr/bin/env bash
# Guard test for the root<->module variable contract and module call depth.
# Root variables must stay a subset of module variables so interface drift
# fails in CI; module call depth must stay at one.
# Run locally: bash tests/module_sync_test.sh (no AWS required).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

# (a) Every root variable must also exist in its module's variables.tf,
# except root-only variables on the allowlist (currently just `region`).
root_only_allowlist="region"
pairs=(
  "pipeline/account-bootstrap modules/account-bootstrap"
  "pipeline/account-vending modules/account-vending"
  "01-management-init-role-and-hardening modules/ci"
)

for pair in "${pairs[@]}"; do
  read -r root_dir module_dir <<< "$pair"
  root_vars="$(rg -o '^\s*variable\s+"[^"]+"' "$ROOT/$root_dir/variables.tf" | sed -E 's/.*"([^"]+)"$/\1/' | sort -u)"
  module_vars="$(rg -o '^\s*variable\s+"[^"]+"' "$ROOT/$module_dir/variables.tf" | sed -E 's/.*"([^"]+)"$/\1/' | sort -u)"
  missing="$(comm -23 <(printf '%s\n' "$root_vars") <(printf '%s\n' "$module_vars") | grep -vx "$root_only_allowlist" || true)"
  if [[ -n "$missing" ]]; then
    fail "$root_dir declares variables missing from $module_dir: $(printf '%s' "$missing" | tr '\n' ' ')"
  fi
done

# (b) No module blocks may exist inside the modules/ tree; module call depth
# stays at one (exclude .terraform directories).
nested_modules="$(rg -n '^\s*module\s+"' "$ROOT/modules" --glob '!**/.terraform/**' || true)"
if [[ -n "$nested_modules" ]]; then
  fail "module blocks found inside modules/ (module call depth must stay at one): $nested_modules"
fi

echo "PASS: module sync tests"
