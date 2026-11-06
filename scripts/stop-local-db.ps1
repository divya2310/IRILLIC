$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$dataDir = Join-Path $projectRoot ".local-postgres\data"
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
if (-not (Test-Path -LiteralPath (Join-Path $dataDir "PG_VERSION"))) { Write-Host "Local IRILLIC database is not initialized."; exit 0 }
$client = New-Object Net.Sockets.TcpClient
try { $client.Connect("127.0.0.1", 5433); $running = $true }
catch { $running = $false } finally { $client.Dispose() }
if (-not $running) { Write-Host "IRILLIC PostgreSQL is already stopped."; exit 0 }
& $pgCtl -D $dataDir stop -m fast
if ($LASTEXITCODE -ne 0) { throw "IRILLIC PostgreSQL could not be stopped." }
Write-Host "IRILLIC PostgreSQL stopped."
