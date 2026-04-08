[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Command,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path

. (Join-Path $root 'lib\output.ps1')
. (Join-Path $root 'lib\git.ps1')

$commandMap = @{
    'status'       = Join-Path $root 'commands\status.ps1'
    'summary'      = Join-Path $root 'commands\summary.ps1'
    'sync'         = Join-Path $root 'commands\sync.ps1'
    'commit'       = Join-Path $root 'commands\commit.ps1'
    'branch-clean' = Join-Path $root 'commands\branch-clean.ps1'
    'help'         = $null
}

function Show-Help {
    Write-Section 'TOI Git'
    Write-Host 'Usage: .\toi.ps1 <command> [args]'
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  status        Show compact branch and working tree status'
    Write-Host '  summary       Show recent commits and working tree overview'
    Write-Host '  sync          Fetch remotes and show branch tracking state'
    Write-Host '  commit        Create a commit with a message'
    Write-Host '  branch-clean  List or delete merged local branches'
}

if (-not $Command) {
    Show-Help
    exit 0
}

$normalizedCommand = $Command.ToLowerInvariant()

if (-not $commandMap.ContainsKey($normalizedCommand)) {
    Write-ErrorLine "Unknown command: $Command"
    Write-Host ''
    Show-Help
    exit 1
}

if ($normalizedCommand -eq 'help') {
    Show-Help
    exit 0
}

$commandPath = $commandMap[$normalizedCommand]
. $commandPath
Invoke-ToiCommand -Arguments $Arguments
