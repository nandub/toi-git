function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $remoteUrl = Get-RemoteUrl
    if (-not $remoteUrl) {
        throw 'No origin remote is configured.'
    }

    $browseUrl = Convert-RemoteToBrowseUrl -RemoteUrl $remoteUrl
    $target = if ($Arguments.Count -gt 0) { $Arguments[0].ToLowerInvariant() } else { 'repo' }
    $currentBranch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName

    switch ($target) {
        'repo' {
            $finalUrl = $browseUrl
        }
        'branch' {
            $finalUrl = Get-BranchBrowseUrl -RepositoryUrl $browseUrl -BranchName $currentBranch
        }
        'compare' {
            if ($currentBranch -eq $defaultBranch) {
                throw 'Compare view is only useful from a non-default branch.'
            }

            $finalUrl = Get-CompareBrowseUrl -RepositoryUrl $browseUrl -BaseBranch $defaultBranch -HeadBranch $currentBranch
        }
        'pr' {
            if ($currentBranch -eq $defaultBranch) {
                throw 'PR view is only useful from a non-default branch.'
            }

            $finalUrl = Get-PullRequestBrowseUrl -RepositoryUrl $browseUrl -BaseBranch $defaultBranch -HeadBranch $currentBranch
        }
        default {
            throw 'Usage: .\toi.ps1 open [repo|branch|compare|pr]'
        }
    }

    Write-Section 'Open'
    Write-InfoLine $finalUrl

    Start-Process $finalUrl | Out-Null
}
