# Servoy CI/CD Example

Reference implementation for running Servoy validation and staged database migrations with GitHub Actions, including a self-hosted runner path for private-network MySQL access.

> [!IMPORTANT]
> This repository is designed around **manual control for staging/production** and **reusable workflow composition**. PR checks stay fast and shared logic is centralized.

## What this repository provides

- Reusable Servoy CI workflow used by thin caller workflows
- PR validation workflow for non-draft pull requests
- Manual staging and production validation workflows
- Manual staging Prisma migration workflow on self-hosted runners
- Local Docker examples for:
  - Linux self-hosted runner container
  - Mock staging MySQL container on a shared Docker network

## Workflow map

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `pr-validation.yml` | `pull_request` | Runs shared Servoy validation for PRs |
| `staging-validation.yml` | `workflow_dispatch` | Manual staging validation from `main` |
| `production-validation.yml` | `workflow_dispatch` | Manual production validation with explicit `servoy_release_tag` |
| `staging-migrations.yml` | `workflow_dispatch` | Runs Prisma migrations on self-hosted staging runner |
| `runner-smoke-test.yml` | `workflow_dispatch` | Manual runner/network smoke test |
| `reusable-servoy-ci.yml` | `workflow_call` | Shared execution logic used by callers |

## Required GitHub configuration

### Repository secrets

- `SERVOY_ASSET_TOKEN` (read access to private Servoy assets release repo)

### Repository variables

- `SERVOY_ASSETS_REPO` in `owner/repo` format

### Staging environment

Create environment `staging` and set:

- `APPDB_DATABASE_URL` (preferred) or `STAGING_DB_URL`

Expected URL format:

```text
mysql://USER:PASSWORD@HOST:3306/DATABASE
```

## Staging migration flow

`staging-migrations.yml`:

1. Selects self-hosted runner labels: `self-hosted`, `staging`, `office-net`
2. Validates DB URL secret
3. Verifies TCP reachability to MySQL from runner network path
4. Runs:
   - `npm run prisma:validate:appdb`
   - `npm run prisma:migrate:appdb`
   - `npm run prisma:status:appdb`

> [!TIP]
> Keep `stopOnDataModelChanges` behavior on runtime nodes and run schema changes through controlled migration/import jobs.

## Local end-to-end test setup

### 1. Start mock staging MySQL

```powershell
./ci/docker/run-staging-mysql-mock-local.ps1
```

### 2. Start local Linux self-hosted runner

```powershell
./ci/docker/run-github-runner-local.ps1
```

Both scripts use Docker network `staging-net` by default, so containers can resolve each other by name (for example `staging-mysql-mock`).

### 3. Trigger workflow

Run **Staging migrations** from GitHub Actions UI (manual dispatch).

## Project structure

```text
.github/workflows/      # CI/CD workflows
ci/README.md            # Detailed CI operational notes
ci/docker/              # Local runner + mock DB Docker examples
ci/scripts/             # CI helper scripts
prisma/                 # Prisma schema and migrations
```

## Additional docs

For deeper operational details and local helper commands, see [`ci/README.md`](ci/README.md).
