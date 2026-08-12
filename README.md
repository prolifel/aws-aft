# AWS Hardened

OpenTofu module that applies an account- and region-level security baseline:

- Account-level S3 public access block (blocks ACLs, policies, public buckets)
- Strict IAM account password policy
- EBS default encryption
- GuardDuty detector
- CloudTrail trail with SSE-KMS-encrypted, versioned, lifecycle-managed log bucket
- Optional removal of all rules from default security groups per VPC

Every feature is opt-out via its variable (see `variables.tf`).

## Requirements

- OpenTofu `>= 1.8.0` (or Terraform `>= 1.8.0`)
- AWS credentials with permissions for the resources you enable
- Provider `hashicorp/aws` pinned at `6.58.0` (`versions.tf`)

## Usage

```hcl
module "hardened" {
  source = "git::https://github.com/example/aws-hardened.git?ref=v1.0.0"

  default_security_group_vpc_ids = ["vpc-0123456789abcdef0"]
  tags                           = { Environment = "production" }
}
```

See `examples/basic` for a complete standalone example.

## Commands

```sh
tofu init       # download providers, generate lock file
tofu validate   # validate configuration syntax
tofu plan       # show changes before applying
tofu apply      # apply the baseline
tofu test       # run smoke test suite (uses mocks, no AWS account needed)
tofu fmt        # format .tf files
```

## Notes

- The CloudTrail log bucket name is auto-generated from prefix, account ID, and region. Set `cloudtrail.bucket_name` to override.
- `force_destroy` on the log bucket defaults to `false`; set `cloudtrail.force_destroy = true` before destroying the module.
- Removing default security group rules is irreversible; pass VPC IDs explicitly.
