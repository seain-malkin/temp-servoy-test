#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_RUNNER_URL:?GITHUB_RUNNER_URL is required (for example https://github.com/<owner>/<repo>)}"
: "${GITHUB_RUNNER_TOKEN:?GITHUB_RUNNER_TOKEN is required (registration token from GitHub UI/API)}"

RUNNER_NAME="${RUNNER_NAME:-$(hostname)}"
RUNNER_WORKDIR="${RUNNER_WORKDIR:-_work}"
RUNNER_LABELS="${RUNNER_LABELS:-self-hosted,linux,docker}"
RUNNER_GROUP="${RUNNER_GROUP:-Default}"
RUNNER_EPHEMERAL="${RUNNER_EPHEMERAL:-true}"
RUNNER_DISABLEUPDATE="${RUNNER_DISABLEUPDATE:-false}"

cd /home/runner/actions-runner

cleanup() {
  if [[ -n "${GITHUB_RUNNER_REMOVE_TOKEN:-}" ]]; then
    ./config.sh remove --unattended --token "${GITHUB_RUNNER_REMOVE_TOKEN}" || true
  fi
}
trap cleanup EXIT INT TERM

config_args=(
  --url "${GITHUB_RUNNER_URL}"
  --token "${GITHUB_RUNNER_TOKEN}"
  --name "${RUNNER_NAME}"
  --work "${RUNNER_WORKDIR}"
  --runnergroup "${RUNNER_GROUP}"
  --labels "${RUNNER_LABELS}"
  --unattended
  --replace
)

if [[ "${RUNNER_EPHEMERAL}" == "true" ]]; then
  config_args+=(--ephemeral)
fi

if [[ "${RUNNER_DISABLEUPDATE}" == "true" ]]; then
  config_args+=(--disableupdate)
fi

./config.sh "${config_args[@]}"
exec ./run.sh
