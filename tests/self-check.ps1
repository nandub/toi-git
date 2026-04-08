[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ($Json) {
    powershell -ExecutionPolicy Bypass -File .\toi.ps1 self-check -Json
}
else {
    powershell -ExecutionPolicy Bypass -File .\toi.ps1 self-check
}
