# CI/CD Assets

This directory contains shared infrastructure for GitHub Actions workflows: reusable
Docker images and helpers that are independent of any single environment.

## Directory Structure

```
ci/
  docker/
    toolchain/
      Dockerfile    Base image: JDK 17 + Node 22 + Tomcat 9 (no MySQL, no Servoy binary)
```

## GHCR Images

| Image | Tag | Description |
|---|---|---|
| `ghcr.io/<owner>/<repo>/servoy-toolchain` | `latest` / version tag | Reusable build base |

The toolchain image is built and pushed by
[`.github/workflows/reusable-build-toolchain.yml`](../.github/workflows/reusable-build-toolchain.yml).

## Servoy Binary Dependency

The Servoy runtime (`servoy_linux.<version>.tar.gz`) is **not stored in this repository**.

### CI (GitHub Actions)

The workflow downloads the tarball from a GitHub Release in a dedicated private assets
repository before the Docker build.  Set the following repository secrets/variables:

| Name | Type | Description |
|---|---|---|
| `SERVOY_ASSETS_REPO` | variable | `owner/repo` of the private assets repository |
| `SERVOY_VERSION` | variable | Release tag (e.g. `4046`) |
| `SERVOY_ASSET_TOKEN` | secret | Fine-grained PAT with **Contents: read** on the assets repo |

The workflow step looks like:

```yaml
- name: Download Servoy release asset
  env:
    GH_TOKEN: ${{ secrets.SERVOY_ASSET_TOKEN }}
  run: |
    mkdir -p artifacts
    gh release download "v${{ vars.SERVOY_VERSION }}" \
      --repo "${{ vars.SERVOY_ASSETS_REPO }}" \
      --pattern "servoy_linux.*.tar.gz" \
      --dir artifacts/
```

### Local Development

Place the tarball in the `artifacts/` directory before building:

```
artifacts/
  servoy_linux.<version>.tar.gz   ← download from the private assets repo
```

The `artifacts/` directory is tracked in git (via `.gitkeep`) but tarballs are gitignored.
See `.gitignore` and `.dockerignore` for details.

## Reusable Workflows

| Workflow | Trigger | Purpose |
|---|---|---|
| `reusable-build-toolchain.yml` | `workflow_call` | Builds and optionally pushes the toolchain image to GHCR |
| `reusable-run-tests.yml` | `workflow_call` | Runs integration tests with a MySQL service container |
