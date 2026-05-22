# Copilot instructions for this repository

## Build, test, and lint commands

This repository is validated through a Docker-based integration run; there is no working local lint or unit-test script in `package.json` (`npm test` is a placeholder that exits with error).

### Prerequisites

Place the Servoy runtime tarball (`servoy_linux.<version>.tar.gz`) in the `artifacts/`
directory before building any Docker image.  The file is gitignored; in CI it is
downloaded automatically from a private assets repository (see `ci/README.md`).

### Build the test-e2e image

```bash
docker build -f build/docker/test-e2e/Dockerfile -t servoy-test-e2e .
```

### Local development with Docker Compose (recommended)

```bash
# First time: copy the env template
cp build/docker/test-e2e/.env.local.example build/docker/test-e2e/.env.local

# Build and run (starts MySQL service container automatically)
docker compose up --build
```

### Run the integration test container manually (requires external MySQL)

```bash
docker run --rm \
  -e PROJECT_NAME=<servoy-solution-name> \
  -e ENABLE_LOCAL_MYSQL=false \
  -e REPOSITORY_DB_HOST=<host> \
  -e APP_DB_1_SERVER_NAME=appdb \
  -e APP_DB_1_HOST=<host> \
  -e APP_DB_1_NAME=appdb \
  -e APP_DB_1_USER=<user> \
  servoy-test-e2e
```

This is the same test path used in CI (`.github/workflows/servoy-test.yml`), where
MySQL runs as a GitHub Actions service container.

### Build the staging image

```bash
docker build -f build/docker/staging/Dockerfile -t servoy-staging .
```

### PowerShell helper scripts (advanced — direct docker run, external MySQL required)

```powershell
.\build\docker\test-e2e\run-local.ps1 -Build
.\build\docker\staging\run-local.ps1 -Build
```

## High-level architecture

The repo combines three Servoy projects plus containerized test infrastructure:

1. `servoy_test` is the main solution (`solutionType: 1024`) and declares module dependencies on `svyUtils` and `svySearch` via `modulesNames` and `.buildpath`.
2. `svyUtils` is a reusable module/library (`solutionType: 2`) that provides shared scopes such as logging, events, application core, and utility functions.
3. `svySearch` is another module (`solutionType: 1`) layered on top of `svyUtils` and contains search parsing/query-building logic.
4. `build/docker/test-e2e/Dockerfile` and `build/docker/staging/Dockerfile` define environment-specific container builds.
5. `build/entrypoint.sh` orchestrates the integration flow: initialize MySQL (optional), render env-specific `servoy.properties` from template variables, export WAR from local `/workspace/src` using Servoy `war_export.sh`, deploy to Tomcat, then health-check the app.

## Key conventions in this codebase

1. Servoy metadata annotations (`@properties={typeid:...,uuid:"..."}`) are pervasive in `.js` and form files; preserve them when editing methods/variables.
2. Module lifecycle follows `svyUtils/forms/AbstractModuleDef.js`: module defs provide `getId`, `getVersion`, optional `getDependencies`, and `moduleInit`; `scopes.svyApplicationCore.initModules(...)` discovers and initializes them in dependency order.
3. Inter-module dependencies are encoded in both `.buildpath` and solution metadata (`rootmetadata.obj` / `solution_settings.obj`); keep these aligned when adding/removing modules.
4. CI and Docker build paths depend on the existing `artificats/` directory name (including spelling) referenced by `.github/workflows/servoy-test.yml` and the environment Dockerfiles under `build/docker/`.
