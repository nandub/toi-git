function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $delta = Get-ToiCommitDelta -Direction 'outgoing'

    if ($json) {
        Write-Json $delta
        return
    }

    Write-Section 'Outgoing'
    Write-KeyValue 'Branch' $delta.branch

    if (-not $delta.available) {
        Write-InfoLine $delta.reason
        return
    }

    Write-KeyValue 'Compare Ref' $delta.compare_ref
    Write-KeyValue 'Outgoing Commits' $delta.count

    if ($delta.count -eq 0) {
        Write-SuccessLine 'No outgoing commits.'
        return
    }

    Write-Section 'Commits'
    $delta.commits | ForEach-Object { Write-BulletLine $_ }
}
