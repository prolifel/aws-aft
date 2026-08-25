# Replace AWS Config via Control Tower delegation

# Superseded by ADR-0002 (vending-only scope) and ADR-0004 (no CloudFormation/native OpenTofu baseline).

This repo was previously hardened with AWS Config centralized through a Control Tower delegated admin. As of the vending-only reconstruction, this repo no longer owns AWS Config, audit logging, or Config rule enforcement; those concerns are managed in a separate repo.
