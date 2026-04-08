function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $snapshot = $Arguments -contains '-Snapshot'
    $writeSnapshot = $Arguments -contains '-WriteSnapshot'
    $schema = if ($snapshot) { Get-ToiSchemaSnapshotModel } else { Get-ToiSchemaModel }

    if ($writeSnapshot) {
        $snapshotPath = Get-ToiContractSnapshotPath
        $snapshotJson = Convert-ToiValueToCanonicalJson -Value (Get-ToiSchemaSnapshotModel)
        $snapshotDirectory = Split-Path -Parent $snapshotPath

        if (-not (Test-Path -LiteralPath $snapshotDirectory)) {
            New-Item -ItemType Directory -Path $snapshotDirectory -Force | Out-Null
        }

        Set-Content -LiteralPath $snapshotPath -Value $snapshotJson

        if ($json) {
            Write-Json ([PSCustomObject]@{
                updated = $true
                path = $snapshotPath
                contract_version = (Get-ToiContractVersion)
            })
            return
        }

        Write-Section 'Schema'
        Write-SuccessLine "Updated contract snapshot: $snapshotPath"
        Write-InfoLine "Contract version: $(Get-ToiContractVersion)"
        return
    }

    if ($json) {
        Write-Json $schema
        return
    }

    $markdown = Convert-ToiSchemaToMarkdown -Schema $schema
    Write-Host $markdown
}
