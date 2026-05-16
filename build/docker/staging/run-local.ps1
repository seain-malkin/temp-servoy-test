param(
    [switch]$Build,
    [string]$EnvFile = ".env.local",
    [string]$ImageTag = "servoy-staging"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..\..\..")
$dockerfile = Join-Path $repoRoot "build\docker\staging\Dockerfile"

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
