# Control Tower Account Vending

This repo vends and reconciles AWS accounts in a Control Tower organization from declarative account requests. It owns the vending lifecycle and the mandatory per-account baseline; it does not own security-service enablement or org-level hardening.

## Language

**Account Request**:
A declarative YAML file that describes one desired AWS account: identity fields, target OU, owner, environment, cost center, regions, and tags.
_Avoid_: account spec, account manifest

**Vending**:
Creating and enrolling an AWS account through Control Tower Account Factory from an account request.
_Avoid_: provisioning, account creation

**Vended Account**:
An AWS account produced by vending an account request.

**Account Factory**:
The Control Tower capability that vends and enrolls accounts into the organization.

**Management Account**:
The AWS account that hosts the Control Tower landing zone and executes vending.

**Baseline**:
The fixed, mandatory set of per-account controls applied to every vended account. Not user-configurable.
_Avoid_: hardening, customization

**Bootstrap**:
Applying the baseline to a vended account after it exists.
_Avoid_: customization, hardening

**Bootstrap Item**:
One discrete baseline control applied during bootstrap (for example, IAM password policy, alternate contacts, default EBS encryption).

**Identity Fields**:
Account fields that become immutable once an account is vended: email, account name, and initial OU.
_Avoid_: immutable attributes

**Reconciliation**:
Aligning a vended account with its account request for non-identity fields: owner, environment, cost center, tags, contacts, and regions.

**Archive**:
Removing an account request from active management while leaving the AWS account intact.
_Avoid_: delete, deprovision, teardown

**Discovery**:
Enumerating AWS accounts in the organization and matching each to an account request or an explicit ignore.

**Unmanaged Account**:
An AWS account found by discovery with no matching account request and no explicit ignore marker.

**Provisioning Operation**:
A single Account Factory operation submitted for one account request.

**Bootstrap Failure Report**:
A machine-readable JSON artifact listing bootstrap items that failed, enabling a targeted rerun without re-vending.

**Owner**:
The team accountable for a vended account.

**Cost Center**:
The billing and accountability value attached to a vended account.

**Per-Account Variable**:
A root variable that varies per account request and is fed by the deployment var-file or `-var` flags.
_Avoid_: passthrough

**Org-Wide Constant**:
A value identical for every account; lives as a literal in the root's module call or as a module default.
_Avoid_: base config
