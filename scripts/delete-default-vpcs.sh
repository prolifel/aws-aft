#!/usr/bin/env bash
set -euo pipefail

# Deletes the default VPC in every enabled region of the calling account.
# Mirrors AFT's delete-default-vpcs feature.

regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)
for region in $regions; do
  vpc_id=$(aws ec2 describe-vpcs --region "$region" \
    --filters Name=isDefault,Values=true \
    --query 'Vpcs[0].VpcId' --output text)
  [[ -z "$vpc_id" || "$vpc_id" == "None" ]] && continue
  echo "deleting default VPC $vpc_id in $region" >&2
  for subnet in $(aws ec2 describe-subnets --region "$region" \
    --filters Name=vpc-id,Values="$vpc_id" \
    --query 'Subnets[].SubnetId' --output text); do
    aws ec2 delete-subnet --region "$region" --subnet-id "$subnet"
  done
  for igw in $(aws ec2 describe-internet-gateways --region "$region" \
    --filters Name=attachment.vpc-id,Values="$vpc_id" \
    --query 'InternetGateways[].InternetGatewayId' --output text); do
    aws ec2 detach-internet-gateway --region "$region" \
      --internet-gateway-id "$igw" --vpc-id "$vpc_id"
    aws ec2 delete-internet-gateway --region "$region" --internet-gateway-id "$igw"
  done
  if aws ec2 delete-vpc --region "$region" --vpc-id "$vpc_id"; then
    continue
  fi
  sleep 5
  if aws ec2 delete-vpc --region "$region" --vpc-id "$vpc_id"; then
    continue
  fi
  echo "WARNING: skipping VPC $vpc_id in $region; delete-vpc still failed (dependencies may still exist)" >&2
done
