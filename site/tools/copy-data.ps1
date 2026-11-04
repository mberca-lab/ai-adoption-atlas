# Copies the aggregated analysis outputs (..\site_data\*.json) into site\data\ so the
# site is self-contained for GitHub Pages. Only writes inside site\data\.
# Usage (from anywhere):  powershell -File site\tools\copy-data.ps1
$ErrorActionPreference = "Stop"
$site = Split-Path -Parent $PSScriptRoot
$src  = Join-Path (Split-Path -Parent $site) "site_data"
$dst  = Join-Path $site "data"
New-Item -ItemType Directory -Force -Path $dst | Out-Null
$files = @("trust_trends.json", "modelling.json", "segments.json")
$copied = @()
foreach ($f in $files) {
  $from = Join-Path $src $f
  if (-not (Test-Path -LiteralPath $from)) { throw "Required export missing: $f" }
  $json = Get-Content -LiteralPath $from -Raw | ConvertFrom-Json
  if ($json.meta.fixture) { throw "Illustrative export cannot be published: $f" }
  if ($f -eq "segments.json" -and $json.meta.status -ne "final") { throw "Segments export is not final." }
}
foreach ($f in $files) {
  $from = Join-Path $src $f
  if (Test-Path $from) {
    # validate JSON before publishing it
    Get-Content $from -Raw | ConvertFrom-Json | Out-Null
    Copy-Item $from (Join-Path $dst $f) -Force
    $copied += $f
    Write-Host "copied  $f"
  } else {
    Remove-Item (Join-Path $dst $f) -ErrorAction SilentlyContinue
    throw "Required export missing: $f"
  }
}
# manifest tells data.js which files exist (avoids 404 probes on GitHub Pages)
$manifest = [ordered]@{ files = $copied; copied_at = (Get-Date).ToString("s") } | ConvertTo-Json -Compress
Set-Content -Path (Join-Path $dst "manifest.json") -Value $manifest -Encoding UTF8
Write-Host "wrote   manifest.json"
