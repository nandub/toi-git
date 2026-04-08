function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $schema = Get-ToiSchemaModel

    if ($json) {
        Write-Json $schema
        return
    }

    $markdown = Convert-ToiSchemaToMarkdown -Schema $schema
    Write-Host $markdown
}
