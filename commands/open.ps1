function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $remoteUrl = Get-RemoteUrl
    if (-not $remoteUrl) {
        throw 'No origin remote is configured.'
    }

    $browseUrl = Convert-RemoteToBrowseUrl -RemoteUrl $remoteUrl

    Write-Section 'Open'
    Write-InfoLine $browseUrl

    Start-Process $browseUrl | Out-Null
}
