param(
    [switch]$Build,
    [string]$EnvFile = ".env.local",
    [string]$ImageTag = "servoy-test-e2e"
)

# NOTE: MySQL is no longer bundled in the image.
# Use docker-compose.yml at the repo root for local development, which provides an
# external MySQL service container and sets the correct DB env vars automatically:
#
#   docker compose up --build
#
# This script is retained for advanced scenarios where you run the image directly
# against an already-running external MySQL.  Ensure ENABLE_LOCAL_MYSQL=false and
# the REPOSITORY_DB_* / APP_DB_1_* variables in your env file point to that MySQL.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..\..")
$dockerfile = Join-Path $repoRoot "build\docker\test-e2e\Dockerfile"

if ($Build) {
    docker build -f "$dockerfile" -t $ImageTag "$repoRoot"
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

$envFilePath = if ([System.IO.Path]::IsPathRooted($EnvFile)) { $EnvFile } else { Join-Path $scriptDir $EnvFile }
if (-not (Test-Path $envFilePath)) {
    Write-Error "Env file not found: $envFilePath"
    Write-Host "Create it from: $(Join-Path $scriptDir '.env.local.example')" -ForegroundColor Yellow
    exit 1
}

docker run --rm --env-file "$envFilePath" $ImageTag
