param(
    [string]$EnvFile = "ci/docker/.env.runner.local",
    [string]$Image = "gh-runner-example",
    [string]$NetworkName = "staging-net",
    [switch]$SkipEnsureNetwork
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $EnvFile)) {
    throw "Env file not found: $EnvFile"
}

$envLines = Get-Content $EnvFile
foreach ($line in $envLines) {
    $trimmed = $line.Trim()
    if ($trimmed -eq "" -or $trimmed.StartsWith("#")) {
        continue
    }

    $parts = $trimmed -split "=", 2
    if ($parts.Count -ne 2) {
        continue
    }

    $key = $parts[0].Trim()
    $value = $parts[1].Trim().Trim('"')
    [Environment]::SetEnvironmentVariable($key, $value, "Process")
}

if (-not $env:GITHUB_RUNNER_URL) {
    throw "GITHUB_RUNNER_URL must be set in $EnvFile"
}

if (-not $SkipEnsureNetwork) {
    $networkExists = docker network ls --filter "name=^${NetworkName}$" --format "{{.Name}}"
    if (-not $networkExists) {
        Write-Host "Creating Docker network '$NetworkName' ..."
        docker network create $NetworkName | Out-Null
    }
}

docker image inspect $Image *> $null
if ($LASTEXITCODE -ne 0) {
    throw "Docker image '$Image' not found. Build it first."
}

$uri = [Uri]$env:GITHUB_RUNNER_URL
$segments = $uri.AbsolutePath.Trim("/").Split("/")

if ($segments.Count -ge 2) {
    $owner = $segments[0]
    $repo = $segments[1]
    $endpoint = "repos/$owner/$repo/actions/runners/registration-token"
} elseif ($segments.Count -eq 1 -and $segments[0]) {
    $org = $segments[0]
    $endpoint = "orgs/$org/actions/runners/registration-token"
} else {
    throw "Cannot infer repository or organization from GITHUB_RUNNER_URL: $($env:GITHUB_RUNNER_URL)"
}

$token = gh api --method POST $endpoint --jq ".token"
if (-not $token) {
    throw "Failed to fetch a runner registration token via gh."
}

Write-Host "Starting runner container using $EnvFile ..."
docker run --rm -it `
  --network $NetworkName `
  --env-file $EnvFile `
  -e "GITHUB_RUNNER_TOKEN=$token" `
  $Image
