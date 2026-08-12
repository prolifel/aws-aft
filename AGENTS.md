# Repository Guidelines

Contributor guide for the AWS Hardened OpenTofu module.

## Project Structure & Module Organization

- Root: module composition — `main.tf`, `variables.tf`, `outputs.tf`, `versions.tf`
- `modules/`: five control families — `identity/`, `scp/`, `audit/`, `encryption/`, `detection/`
- `examples/basic/`: standalone usage example; keep it runnable with `tofu init && tofu apply`
- `tests/`: `*.tftest.hcl` smoke tests for `tofu test`
- `docs/superpowers/`: design spec and implementation plan
- `README.md`: usage, requirements, and operational notes

Org-level resources live behind `management_account = true`; per-account resources behind
`false`. New hardening features belong in the matching family module with their own
`*_enabled` flag.

## Build, Test, and Development Commands

- `tofu init` — download providers and generate the lock file
- `tofu validate` — check configuration syntax
- `tofu fmt` — auto-format all `.tf` files
- `tofu test` — run smoke tests with mocked AWS provider (no credentials needed)
- `tofu plan` / `tofu apply` — preview and apply changes

OpenTofu `>= 1.8.0` required. The AWS provider version is pinned exactly in `versions.tf`; bump it deliberately and verify with `tofu validate`.

## Coding Style & Naming Conventions

- HCL, 2-space indentation, snake_case identifiers
- No comments inside resource blocks; put rationale in `description` fields or `README.md`
- Name resources by feature, not resource type: `this`, `strict`, `cloudtrail`
- Keep locals for derived values (e.g., generated bucket names) only
- Run `tofu fmt` before submitting; the diff must be format-clean

## Testing Guidelines

- Tests live in `tests/` as `.tftest.hcl` files using `mock_provider "aws" {}` so they run without an AWS account
- Add a `run` block per hardening feature; assert that feature resources appear in the plan
- Keep tests deterministic: no timestamps, no external calls
- Verify with `tofu test` after any resource change

## Commit & Pull Request Guidelines

- Conventional Commits: `feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`
- One logical change per commit; reference the issue number when one exists
- PRs: concise description of the change and why, mention any variable/output changes, and note breaking behavior (e.g., replaced resources)
- Run `tofu fmt`, `tofu validate`, and `tofu test` before opening a PR
- Tag releases with `vX.Y.Z` for use as module `ref` in consumers

## Security & Configuration Tips

- Never commit real AWS account IDs, ARNs, or credentials
- Defaults favor security; changing a default requires a stated reason in the PR
- Removing default security group rules is irreversible — document it in the README when extended
