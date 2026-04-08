function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArguments,

        [switch]$AllowFailure
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $process = Start-Process -FilePath 'git' `
            -ArgumentList $GitArguments `
            -NoNewWindow `
            -Wait `
            -PassThru `
            -RedirectStandardOutput $stdoutPath `
            -RedirectStandardError $stderrPath

        $exitCode = $process.ExitCode

        $stdoutLines = if (Test-Path -LiteralPath $stdoutPath) {
            @(Get-Content -LiteralPath $stdoutPath)
        }
        else {
            @()
        }

        $stderrLines = if (Test-Path -LiteralPath $stderrPath) {
            @(Get-Content -LiteralPath $stderrPath)
        }
        else {
            @()
        }

        $result = @($stdoutLines + $stderrLines)
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $message = if ($result) { ($result -join [Environment]::NewLine) } else { 'Git command failed.' }
        throw $message
    }

    return [PSCustomObject]@{
        Output   = @($result)
        ExitCode = $exitCode
    }
}

function Test-InGitRepository {
    $result = Invoke-Git -GitArguments @('rev-parse', '--is-inside-work-tree') -AllowFailure
    return $result.ExitCode -eq 0 -and ($result.Output | Select-Object -First 1) -eq 'true'
}

function Assert-InGitRepository {
    if (-not (Test-InGitRepository)) {
        throw 'Run this command inside a Git repository.'
    }
}

function Get-CurrentBranchName {
    $result = Invoke-Git -GitArguments @('branch', '--show-current')
    return ($result.Output | Select-Object -First 1).Trim()
}

function Get-StatusLines {
    $result = Invoke-Git -GitArguments @('status', '--short', '--branch')
    return @($result.Output)
}

function Get-DefaultProtectedBranches {
    return @('main', 'master', 'develop', 'dev')
}

function Test-HasCommits {
    $result = Invoke-Git -GitArguments @('rev-parse', '--verify', 'HEAD') -AllowFailure
    return $result.ExitCode -eq 0
}
