param(
    [switch]$Build,
    [string]$EnvFile = ".env.local",
    [string]$ImageTag = "servoy-test-e2e"
)

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
