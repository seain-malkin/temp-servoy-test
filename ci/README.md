# CI Workflows

This repository uses a shared workflow engine and thin caller workflows:

- `.github/workflows/reusable-servoy-ci.yml` (shared pipeline)
- `.github/workflows/pr-validation.yml` (PR caller)
- `.github/workflows/staging-validation.yml` (manual staging caller)

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
