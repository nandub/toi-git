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
    'save'         = Join-Path $root 'commands\save.ps1'
    'undo'         = Join-Path $root 'commands\undo.ps1'
    'open'         = Join-Path $root 'commands\open.ps1'
    'worktree'     = Join-Path $root 'commands\worktree.ps1'
    'start'        = Join-Path $root 'commands\start.ps1'
    'doctor'       = Join-Path $root 'commands\doctor.ps1'
    'ship'         = Join-Path $root 'commands\ship.ps1'
    'publish'      = Join-Path $root 'commands\publish.ps1'
    'pr'           = Join-Path $root 'commands\pr.ps1'
    'review'       = Join-Path $root 'commands\review.ps1'
    'dashboard'    = Join-Path $root 'commands\dashboard.ps1'
    'next'         = Join-Path $root 'commands\next.ps1'
    'note'         = Join-Path $root 'commands\note.ps1'
    'self-check'   = Join-Path $root 'commands\self-check.ps1'
    'report'       = Join-Path $root 'commands\report.ps1'
    'schema'       = Join-Path $root 'commands\schema.ps1'
    'version'      = Join-Path $root 'commands\version.ps1'
    'install'      = Join-Path $root 'commands\install.ps1'
    'stack'        = Join-Path $root 'commands\stack.ps1'
    'release'      = Join-Path $root 'commands\release.ps1'
    'hotfix'       = Join-Path $root 'commands\hotfix.ps1'
    'bisect'       = Join-Path $root 'commands\bisect.ps1'
    'help'         = $null
}

function Show-Help {
    Write-Section 'TOI Git'
    Write-Host 'Usage: toi <command> [args]'
    Write-Host ''
    Write-Host 'Commands:'
    Write-Host '  status        Show compact branch and working tree status'
    Write-Host '  summary       Show recent commits and working tree overview'
    Write-Host '  sync          Fetch remotes and show branch tracking state'
    Write-Host '  commit        Create a commit with a message'
    Write-Host '  branch-clean  List or delete merged local branches'
    Write-Host '  save          Stage everything and create a checkpoint commit'
    Write-Host '  undo          Undo the last commit with a safe reset mode'
    Write-Host '  open          Open the repository remote in a browser'
    Write-Host '  worktree      List or add Git worktrees'
    Write-Host '  start         Create a typed branch with TOI naming rules'
    Write-Host '  doctor        Inspect repo state and suggest next actions'
    Write-Host '  ship          Check branch readiness for push or PR'
    Write-Host '  publish       Push the current branch and show the PR path'
    Write-Host '  pr            Show PR status, checks, or ready state with gh'
    Write-Host '  review        Summarize PR review pressure and next steps'
    Write-Host '  dashboard     Show a consolidated workflow overview'
    Write-Host '  next          Show the most likely next action'
    Write-Host '  note          Set or show a local note for the current branch'
    Write-Host '  self-check    Run lightweight local verification for TOI Git'
    Write-Host '  report        Generate a workflow report in markdown or json'
    Write-Host '  schema        Show, check, or refresh JSON automation contracts'
    Write-Host '  version       Show module, tag, and current commit version info'
    Write-Host '  install       Install TOI Git for easier global shell usage'
    Write-Host '  stack         Create or restack dependent branches'
    Write-Host '  release       Start a release branch'
    Write-Host '  hotfix        Start a hotfix branch from the default branch'
    Write-Host '  bisect        Guide a git bisect debugging session'
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

