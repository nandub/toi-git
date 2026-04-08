[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$artifacts = @(
    'toi-self-check.json',
    'toi-report.md',
    'toi-report.json',
    'toi-schema.json'
)

Remove-Item $artifacts -Force -ErrorAction SilentlyContinue

$selfCheck = & pwsh -NoProfile -ExecutionPolicy Bypass -File ./tests/self-check.ps1 -Json
$selfCheck | Out-File -FilePath toi-self-check.json -Encoding utf8

$report = & pwsh -NoProfile -ExecutionPolicy Bypass -File ./toi.ps1 report
$report | Out-File -FilePath toi-report.md -Encoding utf8

$reportJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File ./toi.ps1 report -Json
$reportJson | Out-File -FilePath toi-report.json -Encoding utf8

$schema = & pwsh -NoProfile -ExecutionPolicy Bypass -File ./toi.ps1 schema -Json -Snapshot
$schema | Out-File -FilePath toi-schema.json -Encoding utf8

foreach ($artifact in $artifacts) {
    $item = Get-Item $artifact
    if ($item.Length -le 0) {
        throw "Artifact '$artifact' is empty."
    }

    Write-Host "$artifact $($item.Length) bytes"
}
