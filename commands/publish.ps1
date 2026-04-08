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
    $qualityGateMode = Get-QualityGateMode

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
    $validationSuite = Invoke-ToiValidationSuite
    $failedChecks = @($validationSuite.Failed)

    if ($validationSuite.HasChecks) {
        Write-Section 'Quality Gates'
        foreach ($result in $validationSuite.Results) {
            if ($result.Success) {
                Write-SuccessLine "PASS  $($result.Command)"
            }
            else {
                if ($qualityGateMode -eq 'block') {
                    Write-ErrorLine "FAIL  $($result.Command)"
                }
                else {
                    Write-WarningLine "WARN  $($result.Command)"
                }
            }

            $result.Output | Select-Object -First 5 | ForEach-Object { Write-InfoLine "  $_" }
        }

        if ($failedChecks.Count -gt 0 -and $qualityGateMode -eq 'block') {
            throw 'Publish blocked by failing quality gates.'
        }
    }

    Write-Section 'Publish'
    Write-InfoLine "Branch: $branch"
    Write-InfoLine "Dry run: $dryRun"
    Write-InfoLine "Quality gate mode: $qualityGateMode"

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
