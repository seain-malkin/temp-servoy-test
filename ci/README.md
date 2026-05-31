# CI Workflows

This repository uses a shared workflow engine and thin caller workflows:

- `.github/workflows/reusable-servoy-ci.yml` (shared pipeline)
- `.github/workflows/pr-validation.yml` (PR caller)
- `.github/workflows/staging-validation.yml` (manual staging caller)
- `.github/workflows/production-validation.yml` (manual production caller)
- `.github/workflows/staging-migrations.yml` (manual staging DB migration on self-hosted runner)

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

## Staging self-hosted migration workflow

`staging-migrations.yml` is intended for environments where the staging database is reachable only from internal network locations.

Set these for staging:

- Environment: `staging`
- Environment secret: `APPDB_DATABASE_URL` (or `STAGING_DB_URL`)
- Optional variables: `STAGING_RUNNER_LABEL` (default `staging`), `STAGING_NETWORK_LABEL` (default `office-net`)

Workflow behavior:

- manual dispatch only
- run only when dispatched from `main`
- execute on self-hosted runner labels `self-hosted` + staging/network labels
- verify MySQL TCP reachability from the runner network path
- install dependencies, validate Prisma config, run `prisma migrate deploy`
- serialize runs using concurrency group `staging-migrations`

## Optional: local Linux self-hosted runner container example

For learning or local experimentation (including Docker Desktop on Windows), example files are provided:

- `ci/docker/Dockerfile.github-runner.example`
- `ci/docker/entrypoint.github-runner.example.sh`
- `ci/docker/run-github-runner-local.ps1` (auto-fetches a fresh token with `gh`)

This example registers a Linux self-hosted runner using:

- `GITHUB_RUNNER_URL` (repo/org URL)
- `GITHUB_RUNNER_TOKEN` (short-lived registration token)

Recommended for local usage:

- keep it ephemeral (`RUNNER_EPHEMERAL=true`, default)
- pass labels matching workflow constraints (for example `self-hosted,linux,staging,office-net`)
- use a dedicated runner host for real staging/prod access

Start local runner with auto token fetch:

```powershell
./ci/docker/run-github-runner-local.ps1
```

Optional parameters:

```powershell
./ci/docker/run-github-runner-local.ps1 -EnvFile "ci/docker/.env.runner.local" -Image "gh-runner-example"
```
