# Repository Guidelines

Contributor guide for the AWS account-vending repository. This repo vendors AWS accounts through Control Tower Account Factory and applies a mandatory per-account baseline, driven through GitLab CI.

## Project Structure & Module Organization

- `modules/account-vending/`: Control Tower Account Factory vending module (Service Catalog)
- `modules/`: `account-vending/` (Account Factory), `account-bootstrap/` (mandatory baseline), `ci/` (GitLab OIDC + CI role)
- Deployment roots (applied in order): `00-backend/` (state bucket), `01-management-init-role-and-hardening/` (org hardening + gitlab-ci role)
- `02-accounts-creation/`: one declarative account request YAML per account (`template.yaml`)
- `pipeline/`: per-account OpenTofu roots — `account-vending/`, `account-bootstrap/`
- `scripts/`: `validate-accounts.sh`, `account-factory.sh`, `account-bootstrap.sh`
- `examples/basic/`: standalone usage example; keep runnable with `tofu init && tofu apply`
- Tests: `tests/` (Bash scripts exercising request validation)
- `docs/`, `README.md`, `.gitlab-ci.yml`, `ci/`: pipeline definitions and operational notes

Org-level resources live behind `management_account = true`; per-account resources behind `false`. Add new hardening features to the matching family module behind their own `*_enabled` flag. `00-`/`01-` are applied manually once; `02-` and `pipeline/` are pipeline-driven (`docs/gitlab-deployment.md`).

## Build, Test, and Development Commands

- `tofu init` — download providers and generate the lock file
- `tofu validate` — check configuration syntax
- `tofu fmt` — auto-format all `.tf` files
- `tests/validate_test.sh` — deterministic validation logic tests (no AWS required)
- `tofu plan` / `tofu apply` — preview and apply changes

OpenTofu `>= 1.8.0` required. The AWS provider version is pinned exactly in every `versions.tf`; bump it deliberately and verify with `tofu validate`.

## Coding Style & Naming Conventions

- HCL, 2-space indentation, snake_case identifiers
- No comments inside resource blocks; put rationale in `description` fields or `README.md`
- Name resources by feature, not resource type: `this`, `strict`, `cloudtrail`
- Keep locals for derived values only (e.g., generated bucket names)
- Run `tofu fmt` before submitting; the diff must be format-clean

## Testing Guidelines

- Tests live in `tests/` as `.tftest.hcl` files using `mock_provider "aws" {}` so they run without an AWS account
- Add a `run` block per hardening feature; assert the feature's resources appear in the plan
- Keep tests deterministic: no timestamps, no external calls
- Verify with `tofu test` after any resource change

## Commit & Pull Request Guidelines

- Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`, `refactor(scope):`
- One logical change per commit; reference the issue number when one exists
- PRs: concise description of the change and why, mention any variable/output changes, and note breaking behavior (e.g., replaced resources)
- Run `tofu fmt`, `tofu validate`, and `tofu test` before opening a PR
- Tag releases with `vX.Y.Z` for use as module `ref` in consumers

## Security & Configuration Tips

- Never commit real AWS account IDs, ARNs, or credentials
- Defaults favor security; changing a default requires a stated reason in the PR
- Removing default security group rules is irreversible — document it in the README when extended

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues via the `gh` CLI (origin: `prolifel/aws-aft`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default five-role vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
