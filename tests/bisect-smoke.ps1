[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Invoke-ToiJson {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = powershell -NoProfile -ExecutionPolicy Bypass -File .\toi.ps1 @Arguments -Json
    return ($output | ConvertFrom-Json)
}

function Assert-True {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory = $true)]
        $Actual,

        [Parameter(Mandatory = $true)]
        $Expected,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($Actual -ne $Expected) {
        throw "$Message Expected '$Expected' but got '$Actual'."
    }
}

$originalBranchName = git branch --show-current | Select-Object -First 1
$originalBranch = if ($null -ne $originalBranchName) { $originalBranchName.Trim() } else { $null }
$originalRef = if ($originalBranch) { $originalBranch } else { (git rev-parse HEAD).Trim() }
$statusLine = (git status --short --branch | Select-Object -First 1)
$branchName = "chore/bisect-smoke-$([System.Guid]::NewGuid().ToString('N').Substring(0,8))"
$smokeDirectory = Join-Path $root 'scratch'
$smokeTarget = Join-Path $smokeDirectory 'bisect-smoke.txt'
$smokeNote = Join-Path $smokeDirectory 'bisect-note.txt'
$goodCommit = $null
$badCommit = $null
$badRefCommit = $null

if (-not $statusLine -or ($statusLine -notmatch '^\#\# ')) {
    throw 'Unable to determine current branch status.'
}

$porcelain = @(git status --porcelain)
if ($porcelain.Count -gt 0) {
    throw 'Working tree must be clean before running tests/bisect-smoke.ps1.'
}

try {
    powershell -NoProfile -ExecutionPolicy Bypass -File .\toi.ps1 bisect reset | Out-Null
    powershell -NoProfile -ExecutionPolicy Bypass -File .\toi.ps1 start chore ($branchName -replace '^chore/', '') | Out-Null

    if (-not (Test-Path -LiteralPath $smokeDirectory)) {
        New-Item -ItemType Directory -Path $smokeDirectory -Force | Out-Null
    }

    Set-Content -LiteralPath $smokeTarget -Value 'state=good'
    git add -- $smokeTarget
    git commit -m "test(bisect): add good baseline" | Out-Null
    $goodCommit = (git rev-parse HEAD).Trim()

    Set-Content -LiteralPath $smokeTarget -Value 'state=bad'
    git add -- $smokeTarget
    git commit -m "test(bisect): introduce bad state" | Out-Null
    $badCommit = (git rev-parse HEAD).Trim()

    Set-Content -LiteralPath $smokeNote -Value 'this commit is intentionally unrelated to the regression'
    git add -- $smokeNote
    git commit -m "test(bisect): add unrelated follow-up commit" | Out-Null
    $badRefCommit = (git rev-parse HEAD).Trim()

    $start = powershell -NoProfile -ExecutionPolicy Bypass -File .\toi.ps1 bisect start $goodCommit HEAD
    if ((@($start) -join [Environment]::NewLine) -notmatch '== Bisect ==') {
        throw 'Bisect start did not produce the expected section header.'
    }

    $status = Invoke-ToiJson -Arguments @('bisect', 'status')
    Assert-True -Condition $status.active -Message 'Bisect status should be active after start.'
    Assert-Equal -Actual $status.session.good_sha -Expected $goodCommit -Message 'Bisect status should record the good commit SHA.'
    Assert-Equal -Actual $status.session.bad_sha -Expected $badRefCommit -Message 'Bisect status should record the bad commit SHA.'

    $command = "if ((Test-Path '.\scratch\bisect-smoke.txt') -and ((Get-Content '.\scratch\bisect-smoke.txt' -Raw) -match 'state=good')) { exit 0 } else { exit 1 }"
    $run = Invoke-ToiJson -Arguments @('bisect', 'run', $command)
    Assert-True -Condition $run.state.completed -Message 'Bisect run should mark the session as completed.'
    Assert-Equal -Actual $run.state.first_bad_commit.sha -Expected $badCommit -Message 'Bisect run should identify the known bad commit.'

    $report = Invoke-ToiJson -Arguments @('bisect', 'report')
    Assert-True -Condition $report.completed -Message 'Bisect report should show a completed session.'
    Assert-Equal -Actual $report.first_bad_commit.sha -Expected $badCommit -Message 'Bisect report should preserve the culprit SHA.'

    $log = Invoke-ToiJson -Arguments @('bisect', 'log')
    Assert-True -Condition ($log.steps.Count -gt 0) -Message 'Bisect log should preserve recorded steps after completion.'

    $reset = Invoke-ToiJson -Arguments @('bisect', 'reset')
    Assert-True -Condition $reset.reset -Message 'Bisect reset should report a reset after completion.'
    Assert-Equal -Actual $reset.restored_branch -Expected $branchName -Message 'Bisect reset should preserve the original branch name.'
}
finally {
    try {
        powershell -NoProfile -ExecutionPolicy Bypass -File .\toi.ps1 bisect reset | Out-Null
    }
    catch {
    }

    try {
        $currentBranchName = git branch --show-current | Select-Object -First 1
        $currentBranch = if ($null -ne $currentBranchName) { $currentBranchName.Trim() } else { $null }
        if ($currentBranch -ne $originalBranch) {
            git checkout $originalRef | Out-Null
        }
    }
    catch {
    }

    try {
        git branch -D $branchName | Out-Null
    }
    catch {
    }
}

Write-Host "Bisect smoke passed on branch $branchName"
