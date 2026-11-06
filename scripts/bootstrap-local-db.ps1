param(
  [Parameter(Mandatory = $true)]
  [ValidateLength(12, 128)]
  [ValidatePattern('^[^"\r\n]+$')]
  [string]$AdminPassword,
  [string]$AdminEmail = "admin@irillic.com",
  [string]$AdminName = "IRILLIC Admin"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$localRoot = Join-Path $projectRoot ".local-postgres"
$dataDir = Join-Path $localRoot "data"
$envFile = Join-Path $projectRoot ".env.local"
$pgBin = $env:PG_BIN
if (-not $pgBin -or -not (Test-Path -LiteralPath (Join-Path $pgBin "initdb.exe"))) {
  $discovered = Get-ChildItem -Path "C:\Program Files\PostgreSQL\*\bin\initdb.exe" -ErrorAction SilentlyContinue |
    Sort-Object { try { [int]($_.Directory.Parent.Name) } catch { 0 } } -Descending |
    Select-Object -First 1
  if ($discovered) { $pgBin = $discovered.DirectoryName }
}
if (-not $pgBin) {
  $cmd = Get-Command initdb.exe -ErrorAction SilentlyContinue
  if ($cmd) { $pgBin = Split-Path -Parent $cmd.Source }
}
if (-not $pgBin -or -not (Test-Path -LiteralPath (Join-Path $pgBin "initdb.exe"))) {
  throw "PostgreSQL is not found. Set PG_BIN or install PostgreSQL under 'C:\Program Files\PostgreSQL'."
}
$initDb = Join-Path $pgBin "initdb.exe"
$psql = Join-Path $pgBin "psql.exe"
$createdb = Join-Path $pgBin "createdb.exe"
New-Item -ItemType Directory -Path $localRoot -Force | Out-Null
$clusterExists = Test-Path -LiteralPath (Join-Path $dataDir "PG_VERSION")

$dbPassword = $null
if (Test-Path -LiteralPath $envFile) {
  $existingEnv = Get-Content -LiteralPath $envFile -Raw
  if ($existingEnv -match 'DATABASE_URL=postgresql://irillic_app:([^@]+)@127\.0\.0\.1:5433/irillic') { $dbPassword = [Uri]::UnescapeDataString($Matches[1]) }
}
if ($clusterExists -and -not $dbPassword) {
  throw "An existing local database cluster was found, but its matching DATABASE_URL is missing from .env.local. Restore that file or remove the project-local cluster before bootstrapping again."
}
if (-not $dbPassword) {
  $passwordBytes = New-Object byte[] 24
  $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
  $rng.GetBytes($passwordBytes); $rng.Dispose()
  $dbPassword = ([Convert]::ToBase64String($passwordBytes) -replace '[+/=]', 'A') + "!9aZ"
}

if (-not $clusterExists) {
  $passwordFile = Join-Path $localRoot "init-password.tmp"
  [IO.File]::WriteAllText($passwordFile, $dbPassword, (New-Object Text.UTF8Encoding($false)))
  try {
    & $initDb -D $dataDir -U irillic_app --auth-host=scram-sha-256 --auth-local=scram-sha-256 "--pwfile=$passwordFile" --encoding=UTF8 --locale=C
    if ($LASTEXITCODE -ne 0) { throw "PostgreSQL cluster initialization failed." }
  } finally { Remove-Item -LiteralPath $passwordFile -Force -ErrorAction SilentlyContinue }
}

& (Join-Path $PSScriptRoot "start-local-db.ps1")
$env:PGPASSWORD = $dbPassword
$databaseExists = & $psql -h 127.0.0.1 -p 5433 -U irillic_app -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='irillic'"
if ([string]::IsNullOrWhiteSpace($databaseExists) -or ("$databaseExists".Trim() -ne "1")) {
  & $createdb -h 127.0.0.1 -p 5433 -U irillic_app -O irillic_app irillic
  if ($LASTEXITCODE -ne 0) { throw "IRILLIC database creation failed." }
}

$secretBytes = New-Object byte[] 48
$secretRng = New-Object Security.Cryptography.RNGCryptoServiceProvider
$secretRng.GetBytes($secretBytes); $secretRng.Dispose()
$jwtSecret = [Convert]::ToBase64String($secretBytes)
$encodedDbPassword = [Uri]::EscapeDataString($dbPassword)
$safeName = $AdminName.Replace('"', '\"')
$safeEmail = $AdminEmail.ToLowerInvariant().Replace('"', '\"')
$bootstrapEnv = @"
DATABASE_URL=postgresql://irillic_app:${encodedDbPassword}@127.0.0.1:5433/irillic
NEXT_PUBLIC_APP_URL=http://localhost:3000
NEXT_PUBLIC_APP_NAME=IRILLIC
JWT_SECRET=${jwtSecret}
JWT_EXPIRES_IN=7d
ADMIN_NAME="${safeName}"
ADMIN_EMAIL="${safeEmail}"
ADMIN_PASSWORD="${AdminPassword}"
NODE_ENV=development
"@
[IO.File]::WriteAllText($envFile, $bootstrapEnv, (New-Object Text.UTF8Encoding($false)))

Push-Location $projectRoot
try {
  & npm.cmd run db:migrate
  if ($LASTEXITCODE -ne 0) { throw "Database migration failed." }
  & npm.cmd run db:seed
  if ($LASTEXITCODE -ne 0) { throw "Database seed failed." }
} finally { Pop-Location; Remove-Item Env:PGPASSWORD -ErrorAction SilentlyContinue }

$runtimeEnv = $bootstrapEnv -replace '(?m)^ADMIN_PASSWORD=.*\r?\n?', ''
[IO.File]::WriteAllText($envFile, $runtimeEnv, (New-Object Text.UTF8Encoding($false)))
Write-Host "IRILLIC database, migrations and single administrator are ready on port 5433."
Write-Host "Login email: $($AdminEmail.ToLowerInvariant())"
