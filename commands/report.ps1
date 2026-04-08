function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $report = Get-ToiReportModel

    if ($json) {
        Write-Json $report
        return
    }

    $markdown = Convert-ToiReportToMarkdown -Report $report
    Write-Output $markdown
}
