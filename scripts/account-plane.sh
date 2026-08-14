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
