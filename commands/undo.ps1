function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not (Test-HasCommits)) {
        throw 'There is no commit to undo.'
    }

    $commitCount = Get-CommitCount
    if ($commitCount -lt 2) {
        throw 'Undo is only supported after at least two commits. The initial commit has no parent to reset to.'
    }

    $mode = if ($Arguments -contains '-Soft') {
        '--soft'
    }
    elseif ($Arguments -contains '-Hard') {
        throw 'Hard reset is intentionally not exposed here.'
    }
    else {
        '--mixed'
    }

    Write-Section 'Undo'
    Write-InfoLine "Mode: $mode"

    $result = Invoke-Git -GitArguments @('reset', $mode, 'HEAD~1')
    if ($result.Output.Count -gt 0) {
        $result.Output | ForEach-Object { Write-Host $_ }
    }

    Write-SuccessLine 'Last commit undone.'
}
