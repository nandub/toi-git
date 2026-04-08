function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $snapshot = $Arguments -contains '-Snapshot'
    $schema = if ($snapshot) { Get-ToiSchemaSnapshotModel } else { Get-ToiSchemaModel }

    if ($json) {
        Write-Json $schema
        return
    }

    $markdown = Convert-ToiSchemaToMarkdown -Schema $schema
    Write-Host $markdown
}
