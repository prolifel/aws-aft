#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---inventory}"
OUT_DIR="${2:-account_request}"

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
    features="management_account=true;identity=true;scp=true;encryption=true;detection=true"
  else
    features="management_account=false;identity=true;scp=true;encryption=true;detection=true"
  fi

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$id" "$name" "$email" "$status" "$path_str" \
    "${chain[0]}" "$([[ "$id" == "$mgmt_id" ]] && echo true || echo false)" \
    "$scps_str" "$features"
}

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
  done < <(aws organizations list-accounts --output json |
    jq -r '.Accounts[] | "\(.Id) \(.Name) \(.Email) \(.Status)"')
else
  printf '%s\n' "$header"
  printf '%s\n' "${rows[@]}"
fi
