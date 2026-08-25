#!/usr/bin/env bash
set -euo pipefail

ACCOUNT_ID="${1:?usage: account-hardening.sh <account-id>}"
DEPLOY_ROLE="${DEPLOY_ROLE_NAME:-hardened-deploy}"
CT_EXEC_ROLE="AWSControlTowerExecution"
BOOTSTRAP_DIR="${BOOTSTRAP_DIR:-pipeline/account-init-role}"
PLANE_DIR="${PLANE_DIR:-pipeline/account-hardening}"
SESSION="ci-${CI_PIPELINE_ID:-manual}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

assume_role() {
  aws sts assume-role --role-arn "$1" --role-session-name "$SESSION" --output json
}

use_creds() {
  local json="$1"
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
  AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId // empty' <<<"$json")
  AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey // empty' <<<"$json")
  AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken // empty' <<<"$json")
  if [[ -z "$AWS_ACCESS_KEY_ID" || -z "$AWS_SECRET_ACCESS_KEY" || -z "$AWS_SESSION_TOKEN" ]]; then
    echo "ERROR: assume-role returned incomplete credentials: ${json:0:200}" >&2
    exit 1
  fi
  aws sts get-caller-identity --output json >/dev/null || {
    echo "ERROR: assume-role credentials rejected by STS (access_key=${AWS_ACCESS_KEY_ID:0:4}..., session_token_len=${#AWS_SESSION_TOKEN})" >&2
    exit 1
  }
}

json=$(assume_role "arn:aws:iam::${ACCOUNT_ID}:role/${DEPLOY_ROLE}" 2>/dev/null) ||
  json=""

if [[ -n "$json" ]]; then
  echo "$DEPLOY_ROLE already present in $ACCOUNT_ID" >&2
  use_creds "$json"
else
  echo "bootstrapping $DEPLOY_ROLE in $ACCOUNT_ID via $CT_EXEC_ROLE" >&2
  (
    use_creds "$(assume_role "arn:aws:iam::${ACCOUNT_ID}:role/${CT_EXEC_ROLE}")"
    cd "$BOOTSTRAP_DIR"
    tofu init -backend-config="key=${ACCOUNT_ID}/account-init-role.tfstate"
    tofu apply -auto-approve -var "gitlab_ci_role_arn=${CI_ROLE_ARN:?set CI_ROLE_ARN}"
  )
  use_creds "$(assume_role "arn:aws:iam::${ACCOUNT_ID}:role/${DEPLOY_ROLE}")"
fi

if [[ "${DELETE_DEFAULT_VPCS:-0}" == "1" ]]; then
  "$SCRIPT_DIR/delete-default-vpcs.sh"
fi

(
  cd "$PLANE_DIR"
  tofu init -backend-config="key=${ACCOUNT_ID}/account-hardening.tfstate"
  tofu apply -auto-approve \
    -var "config_bucket_name=${CONFIG_BUCKET_ARN##*:::}"
)
