# Copilot instructions for this repository

## Build, test, and lint commands

This repository is validated through a Docker-based integration run; there is no working local lint or unit-test script in `package.json` (`npm test` is a placeholder that exits with error).

### Build the test image

```bash
docker build -f docker/Dockerfile -t servoy-test .
```

### Run the integration test container (single scenario)

```bash
docker run --rm \
  -e REPO_URL=https://github.com/<owner>/<servoy-project-repo> \
  -e REPO_BRANCH=<branch> \
  -e PROJECT_NAME=<servoy-solution-name> \
  [-e GITHUB_TOKEN=<token-for-private-repo>] \
  servoy-test
```

This is the same test path used in CI (`.github/workflows/servoy-test.yml`), where the image is built and then executed with `REPO_URL`, `REPO_BRANCH`, and `PROJECT_NAME`.

## High-level architecture

The repo combines three Servoy projects plus containerized test infrastructure:

1. `servoy_test` is the main solution (`solutionType: 1024`) and declares module dependencies on `svyUtils` and `svySearch` via `modulesNames` and `.buildpath`.
2. `svyUtils` is a reusable module/library (`solutionType: 2`) that provides shared scopes such as logging, events, application core, and utility functions.
3. `svySearch` is another module (`solutionType: 1`) layered on top of `svyUtils` and contains search parsing/query-building logic.
4. `docker/Dockerfile` builds an execution environment containing Servoy runtime, Tomcat, and MySQL.
5. `docker/entrypoint.sh` orchestrates the integration flow: initialize MySQL, clone target project, export WAR using Servoy `war_export.sh`, deploy to Tomcat, then health-check the app.

## Key conventions in this codebase

1. Servoy metadata annotations (`@properties={typeid:...,uuid:"..."}`) are pervasive in `.js` and form files; preserve them when editing methods/variables.
2. Module lifecycle follows `svyUtils/forms/AbstractModuleDef.js`: module defs provide `getId`, `getVersion`, optional `getDependencies`, and `moduleInit`; `scopes.svyApplicationCore.initModules(...)` discovers and initializes them in dependency order.
3. Inter-module dependencies are encoded in both `.buildpath` and solution metadata (`rootmetadata.obj` / `solution_settings.obj`); keep these aligned when adding/removing modules.
4. CI and Docker build paths depend on the existing `artificats/` directory name (including spelling) referenced by `.github/workflows/servoy-test.yml` and `docker/Dockerfile`.
