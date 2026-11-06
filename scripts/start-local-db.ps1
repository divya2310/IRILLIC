$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $projectRoot ".local-postgres\data"
$logFile = Join-Path $projectRoot ".local-postgres\postgres.log"
$pgBin = $env:PG_BIN
if (-not $pgBin -or -not (Test-Path -LiteralPath (Join-Path $pgBin "pg_ctl.exe"))) {
  $discovered = Get-ChildItem -Path "C:\Program Files\PostgreSQL\*\bin\pg_ctl.exe" -ErrorAction SilentlyContinue |
    Sort-Object { try { [int]($_.Directory.Parent.Name) } catch { 0 } } -Descending |
    Select-Object -First 1
  if ($discovered) { $pgBin = $discovered.DirectoryName }
}
if (-not $pgBin) {
  $cmd = Get-Command pg_ctl.exe -ErrorAction SilentlyContinue
  if ($cmd) { $pgBin = Split-Path -Parent $cmd.Source }
}
if (-not $pgBin -or -not (Test-Path -LiteralPath (Join-Path $pgBin "pg_ctl.exe"))) {
  throw "PostgreSQL is not found. Set PG_BIN or install PostgreSQL under 'C:\Program Files\PostgreSQL'."
}
$pgCtl = Join-Path $pgBin "pg_ctl.exe"
if (-not (Test-Path -LiteralPath (Join-Path $dataDir "PG_VERSION"))) { throw "Local IRILLIC database is not initialized. Run scripts\bootstrap-local-db.ps1 first." }

$client = New-Object Net.Sockets.TcpClient
try { $client.Connect("127.0.0.1", 5433); Write-Host "IRILLIC PostgreSQL is already running on port 5433."; exit 0 }
catch { } finally { $client.Dispose() }
& $pgCtl -D $dataDir -l $logFile -o '"-p 5433 -h 127.0.0.1"' start
if ($LASTEXITCODE -ne 0) { throw "IRILLIC PostgreSQL could not be started. See $logFile" }
Write-Host "IRILLIC PostgreSQL started on 127.0.0.1:5433."
