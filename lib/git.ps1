function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArguments,

        [switch]$AllowFailure
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $quotedArguments = $GitArguments | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_ -replace '(\\*)"', '$1$1\"') + '"'
            }
            else {
                $_
            }
        }

        $argumentString = $quotedArguments -join ' '

        $process = Start-Process -FilePath 'git' `
            -ArgumentList $argumentString `
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

function Get-CommitCount {
    if (-not (Test-HasCommits)) {
        return 0
    }

    $result = Invoke-Git -GitArguments @('rev-list', '--count', 'HEAD')
    return [int](($result.Output | Select-Object -First 1).Trim())
}

function Get-RepositoryRoot {
    $result = Invoke-Git -GitArguments @('rev-parse', '--show-toplevel')
    return ($result.Output | Select-Object -First 1).Trim()
}

function Get-RemoteUrl {
    param(
        [string]$RemoteName = 'origin'
    )

    $result = Invoke-Git -GitArguments @('remote', 'get-url', $RemoteName) -AllowFailure

    if ($result.ExitCode -ne 0) {
        return $null
    }

    return ($result.Output | Select-Object -First 1).Trim()
}

function Convert-RemoteToBrowseUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteUrl
    )

    if ($RemoteUrl -match '^git@github\.com:(.+?)(\.git)?$') {
        return "https://github.com/$($matches[1])"
    }

    if ($RemoteUrl -match '^https://github\.com/(.+?)(\.git)?$') {
        return "https://github.com/$($matches[1])"
    }

    return $RemoteUrl -replace '\.git$', ''
}
