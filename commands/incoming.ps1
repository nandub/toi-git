function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $fetch = $Arguments -contains '-Fetch'
    $delta = Get-ToiCommitDelta -Direction 'incoming' -Fetch:$fetch

    if ($json) {
        Write-Json $delta
        return
    }

    Write-Section 'Incoming'
    Write-KeyValue 'Branch' $delta.branch
    Write-KeyValue 'Fetched' $delta.fetched

    if ($delta.fetch_output.Count -gt 0) {
        Write-Section 'Fetch'
        $delta.fetch_output | ForEach-Object { Write-Host $_ }
    }

    if (-not $delta.available) {
        Write-InfoLine $delta.reason
        return
    }

    Write-KeyValue 'Compare Ref' $delta.compare_ref
    Write-KeyValue 'Incoming Commits' $delta.count

    if ($delta.count -eq 0) {
        Write-SuccessLine 'No incoming commits.'
        return
    }

    Write-Section 'Commits'
    $delta.commits | ForEach-Object { Write-BulletLine $_ }
}
