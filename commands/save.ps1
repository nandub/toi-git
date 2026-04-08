function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $message = if ($Arguments -and $Arguments.Count -gt 0) {
        ($Arguments -join ' ').Trim()
    }
    else {
        'WIP: checkpoint'
    }

    Write-Section 'Save'
    Write-InfoLine "Message: $message"

    $statusBefore = Get-StatusLines | Select-Object -Skip 1
    if (-not $statusBefore -or $statusBefore.Count -eq 0) {
        Write-InfoLine 'Nothing to commit.'
        return
    }

    Invoke-Git -GitArguments @('add', '-A') | Out-Null
    $commitResult = Invoke-Git -GitArguments @('commit', '-m', $message)
    $commitResult.Output | ForEach-Object { Write-Host $_ }
}
