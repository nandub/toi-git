function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $branch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName
    $protectedBranches = Get-ProtectedBranches
    $remoteUrl = Get-RemoteUrl
    $openAfterPush = $Arguments -contains '-Open'
    $openPrAfterPush = $Arguments -contains '-Pr'
    $dryRun = $Arguments -contains '-DryRun'

    if ($protectedBranches -contains $branch) {
        throw "Refusing to publish directly from protected branch '$branch'."
    }

    if (-not (Test-WorkingTreeClean)) {
        throw 'Working tree must be clean before publishing.'
    }

    if (-not $remoteUrl) {
        throw 'No origin remote is configured.'
    }

    $upstreamRef = Get-UpstreamRef

    Write-Section 'Publish'
    Write-InfoLine "Branch: $branch"
    Write-InfoLine "Dry run: $dryRun"

    if ($upstreamRef) {
        Write-InfoLine "Upstream: $upstreamRef"
        $gitArguments = if ($dryRun) { @('push', '--dry-run') } else { @('push') }
    }
    else {
        $gitArguments = if ($dryRun) { @('push', '--dry-run', '-u', 'origin', $branch) } else { @('push', '-u', 'origin', $branch) }
    }

    $pushResult = Invoke-Git -GitArguments $gitArguments

    $pushResult.Output | ForEach-Object { Write-Host $_ }

    $repositoryUrl = Convert-RemoteToBrowseUrl -RemoteUrl $remoteUrl
    $branchUrl = Get-BranchBrowseUrl -RepositoryUrl $repositoryUrl -BranchName $branch
    $prUrl = Get-PullRequestBrowseUrl -RepositoryUrl $repositoryUrl -BaseBranch $defaultBranch -HeadBranch $branch

    Write-Section 'Next'
    Write-InfoLine "Branch URL: $branchUrl"
    Write-InfoLine "PR URL: $prUrl"

    if ($dryRun) {
        return
    }

    if ($openPrAfterPush) {
        Start-Process $prUrl | Out-Null
    }
    elseif ($openAfterPush) {
        Start-Process $branchUrl | Out-Null
    }
}
