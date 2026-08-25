#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export FAKE_LOG="$tmp/calls.log"
cat > "$tmp/aws" <<'EOF'
#!/usr/bin/env bash
cmd="$2"
log="${FAKE_LOG:?}"
case "$cmd" in
  describe-regions) echo "ap-southeast-3";;
  describe-vpcs) echo "vpc-123";;
  describe-subnets) echo "subnet-1 subnet-2";;
  describe-internet-gateways) echo "igw-1";;
  delete-subnet) echo "delete-subnet" >> "$log";;
  detach-internet-gateway) echo "detach-internet-gateway" >> "$log";;
  delete-internet-gateway) echo "delete-internet-gateway" >> "$log";;
  delete-vpc)
    echo "delete-vpc" >> "$log"
    if [[ ! -f "$tmp/delete-vpc-ok" ]]; then
      touch "$tmp/delete-vpc-ok"
      echo "An error occurred (DependencyViolation) when calling the DeleteVpc operation: The vpc 'vpc-123' has dependencies and cannot be deleted." >&2
      exit 255
    fi
    ;;
  *) echo "unexpected: $cmd" >> "$log"; exit 1;;
esac
EOF
chmod +x "$tmp/aws"
export PATH="$tmp:$PATH"

scripts/delete-default-vpcs.sh

for expected in \
  delete-subnet \
  delete-subnet \
  detach-internet-gateway \
  delete-internet-gateway \
  delete-vpc \
  delete-vpc; do
  if ! grep -qx "$expected" "$FAKE_LOG" >/dev/null; then
    echo "FAIL: expected $expected" >&2
    echo "--- calls ---" >&2
    cat "$FAKE_LOG" >&2
    exit 1
  fi
done

echo "PASS: default VPC deletion"
