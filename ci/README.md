# CI Workflows

This repository uses a shared workflow engine and thin caller workflows:

- `.github/workflows/reusable-servoy-ci.yml` (shared pipeline)
- `.github/workflows/pr-validation.yml` (PR caller)
- `.github/workflows/staging-validation.yml` (manual staging caller)
- `.github/workflows/production-validation.yml` (manual production caller)

## Required GitHub configuration

Set these at repository level:

- Secret: `SERVOY_ASSET_TOKEN`
- Variable: `SERVOY_ASSETS_REPO` (`owner/repo` containing Servoy release assets)

Release assets in the Servoy assets repository must match:

- `servoy_linux.*.tar.gz`

## Optional staging overrides

These variables are optional and only used by `staging-validation.yml`:

- `SERVOY_ASSETS_REPO_STAGING`
- `STAGING_PROJECT_NAME`
- `STAGING_UNIT_TEST_SOLUTION`

If omitted, staging falls back to:

- `SERVOY_ASSETS_REPO`
- `servoy_test`
- `servoy_unit_tests`

## Optional production overrides

These variables are optional and only used by `production-validation.yml`:

- `SERVOY_ASSETS_REPO_PRODUCTION`
- `PRODUCTION_PROJECT_NAME`
- `PRODUCTION_UNIT_TEST_SOLUTION`

If omitted, production falls back to:

- `SERVOY_ASSETS_REPO`
- `servoy_test`
- `servoy_unit_tests`

Production workflow requires a manual `servoy_release_tag` input so runs are pinned to an explicit immutable release tag.

## Staging workflow guardrails

`staging-validation.yml` is configured to:

- run only when dispatched from `main`
- serialize runs using concurrency group `staging-validation-main`

Note: workflow-level `environment` is not applied directly on reusable-workflow caller jobs. If environment approvals are required, add environment targeting inside the reusable workflow via an explicit input.
