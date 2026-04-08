function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        throw 'Provide a commit message. Example: .\toi.ps1 commit "Add summary command"'
    }

    $message = ($Arguments -join ' ').Trim()

    if (-not $message) {
        throw 'Commit message cannot be empty.'
    }

    Write-Section 'Commit'
    Write-InfoLine "Message: $message"

    $result = Invoke-Git -GitArguments @('commit', '-m', $message)
    $result.Output | ForEach-Object { Write-Host $_ }
}
