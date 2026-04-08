[CmdletBinding()]
param(
    [switch]$Json
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

if ($Json) {
    & .\toi.cmd self-check -Json
}
else {
    & .\toi.cmd self-check
}

