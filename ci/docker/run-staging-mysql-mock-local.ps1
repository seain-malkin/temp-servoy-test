param(
    [string]$Image = "staging-mysql-mock",
    [string]$Dockerfile = "ci/docker/Dockerfile.staging-mysql-mock.example",
    [string]$ContainerName = "staging-mysql-mock",
    [string]$NetworkName = "staging-net",
    [int]$HostPort = 3306,
    [string]$RootPassword = "root",
    [string]$Database = "appdb",
    [string]$User = "appuser",
    [string]$Password = "appsecret",
    [switch]$SkipBuild,
    [switch]$SkipEnsureNetwork
)

$ErrorActionPreference = "Stop"

if (-not $SkipBuild) {
    Write-Host "Building image '$Image' from $Dockerfile ..."
    docker build -f $Dockerfile -t $Image .
}

if (-not $SkipEnsureNetwork) {
    $networkExists = docker network ls --filter "name=^${NetworkName}$" --format "{{.Name}}"
    if (-not $networkExists) {
        Write-Host "Creating Docker network '$NetworkName' ..."
        docker network create $NetworkName | Out-Null
    }
}

$existing = docker ps -a --filter "name=^/${ContainerName}$" --format "{{.ID}}"
if ($existing) {
    Write-Host "Removing existing container '$ContainerName' ..."
    docker rm -f $ContainerName | Out-Null
}

Write-Host "Starting container '$ContainerName' on localhost:$HostPort (network: $NetworkName) ..."
docker run --rm -d --name $ContainerName `
  --network $NetworkName `
  -p "${HostPort}:3306" `
  -e "MYSQL_ROOT_PASSWORD=$RootPassword" `
  -e "MYSQL_DATABASE=$Database" `
  -e "MYSQL_USER=$User" `
  -e "MYSQL_PASSWORD=$Password" `
  $Image | Out-Null

Write-Host "Started: $ContainerName"
Write-Host "Connection URL (from host):"
Write-Host ("mysql://{0}:{1}@127.0.0.1:{2}/{3}" -f $User, $Password, $HostPort, $Database)
Write-Host "Connection URL (from containers on same network):"
Write-Host ("mysql://{0}:{1}@{2}:3306/{3}" -f $User, $Password, $ContainerName, $Database)
