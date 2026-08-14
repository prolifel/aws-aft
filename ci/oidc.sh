#!/usr/bin/env sh
# Sourced by CI jobs. Requires CI_ROLE_ARN variable and id_token OIDC_TOKEN.
creds=$(aws sts assume-role-with-web-identity \
  --role-arn "$CI_ROLE_ARN" \
  --role-session-name "ci-$CI_PIPELINE_ID" \
  --web-identity-token-file "$STS_WEB_IDENTITY_TOKEN_FILE") || exit 1
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
AWS_ACCESS_KEY_ID=$(printf '%s' "$creds" | jq -r .Credentials.AccessKeyId)
AWS_SECRET_ACCESS_KEY=$(printf '%s' "$creds" | jq -r .Credentials.SecretAccessKey)
AWS_SESSION_TOKEN=$(printf '%s' "$creds" | jq -r .Credentials.SessionToken)
