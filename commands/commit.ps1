function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        throw 'Provide a commit message. Example: toi commit "Add summary command"'
    }

    $message = ($Arguments -join ' ').Trim()

    if (-not $message) {
        throw 'Commit message cannot be empty.'
    }

    $commitConvention = Get-CommitConvention
    $branchType = Get-CurrentBranchType

    if ($commitConvention -eq 'required' -and -not (Test-ConventionalCommitMessage -Message $message)) {
        throw ("Commit message does not match the configured convention. " + (Get-CommitConventionHint))
    }

    if ($commitConvention -ne 'off' -and (Test-ConventionalCommitMessage -Message $message) -and -not (Test-AllowedCommitScope -Message $message)) {
        throw ("Commit message scope is not in the configured commitScopes. " + (Get-CommitConventionHint))
    }

    Write-Section 'Commit'
    Write-InfoLine "Message: $message"
    if ($branchType) {
        Write-InfoLine "Branch type: $branchType"
    }

    $result = Invoke-Git -GitArguments @('commit', '-m', $message)
    $result.Output | ForEach-Object { Write-Host $_ }
}

