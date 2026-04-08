function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $branch = Get-CurrentBranchName
    $statusLines = Get-StatusLines | Select-Object -Skip 1

    Write-Section 'Summary'
    Write-Host "Branch: $branch"
    Write-Host "Changed files: $($statusLines.Count)"

    Write-Section 'Recent Commits'
    if (Test-HasCommits) {
        $logResult = Invoke-Git -GitArguments @('log', '--oneline', '--decorate', '-n', '5')
        $logResult.Output | ForEach-Object { Write-Host $_ }
    }
    else {
        Write-InfoLine 'No commits yet.'
    }

    if ($statusLines.Count -gt 0) {
        Write-Section 'Working Tree'
        $statusLines | ForEach-Object { Write-Host $_ }
    }
    else {
        Write-SuccessLine 'Working tree is clean.'
    }
}
