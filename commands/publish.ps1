function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $branch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName
    $protectedBranches = Get-ProtectedBranches
    $remoteUrl = Get-RemoteUrl
    $openAfterPush = $Arguments -contains '-Open'
    $openPrAfterPush = $Arguments -contains '-Pr'
    $dryRun = $Arguments -contains '-DryRun'
    $qualityGateMode = Get-QualityGateMode
    $ghAvailable = Test-GitHubCliAvailable

    if ($protectedBranches -contains $branch) {
        if ($json) {
            Write-Json ([PSCustomObject]@{
                blocked = $true
                reason = "Refusing to publish directly from protected branch '$branch'."
                branch = $branch
            })
            return
        }

        throw "Refusing to publish directly from protected branch '$branch'."
    }

    if (-not (Test-WorkingTreeClean)) {
        if ($json) {
            Write-Json ([PSCustomObject]@{
                blocked = $true
                reason = 'Working tree must be clean before publishing.'
                branch = $branch
            })
            return
        }

        throw 'Working tree must be clean before publishing.'
    }

    if (-not $remoteUrl) {
        if ($json) {
            Write-Json ([PSCustomObject]@{
                blocked = $true
                reason = 'No origin remote is configured.'
                branch = $branch
            })
            return
        }

        throw 'No origin remote is configured.'
    }

    $upstreamRef = Get-UpstreamRef
    $validationSuite = Invoke-ToiValidationSuite
    $failedChecks = @($validationSuite.Failed)

    if ($validationSuite.HasChecks -and -not $json) {
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
            if ($json) {
                Write-Json ([PSCustomObject]@{
                    blocked = $true
                    reason = 'Publish blocked by failing quality gates.'
                    branch = $branch
                    quality_gates = @($validationSuite.Results | ForEach-Object {
                        [PSCustomObject]@{
                            command = $_.Command
                            success = $_.Success
                            exit_code = $_.ExitCode
                        }
                    })
                })
                return
            }

            throw 'Publish blocked by failing quality gates.'
        }
    }

    if (-not $json) {
        Write-Section 'Publish'
        Write-InfoLine "Branch: $branch"
        Write-InfoLine "Dry run: $dryRun"
        Write-InfoLine "Quality gate mode: $qualityGateMode"
        Write-InfoLine "GitHub CLI: $ghAvailable"
    }

    if ($upstreamRef) {
        if (-not $json) {
            Write-InfoLine "Upstream: $upstreamRef"
        }
        $gitArguments = if ($dryRun) { @('push', '--dry-run') } else { @('push') }
    }
    else {
        $gitArguments = if ($dryRun) { @('push', '--dry-run', '-u', 'origin', $branch) } else { @('push', '-u', 'origin', $branch) }
    }

    $pushResult = Invoke-Git -GitArguments $gitArguments

    if (-not $json) {
        $pushResult.Output | ForEach-Object { Write-Host $_ }
    }

    $repositoryUrl = Convert-RemoteToBrowseUrl -RemoteUrl $remoteUrl
    $branchUrl = Get-BranchBrowseUrl -RepositoryUrl $repositoryUrl -BranchName $branch
    $prUrl = Get-PullRequestBrowseUrl -RepositoryUrl $repositoryUrl -BaseBranch $defaultBranch -HeadBranch $branch

    if ($json) {
        Write-Json ([PSCustomObject]@{
            branch = $branch
            dry_run = $dryRun
            quality_gate_mode = $qualityGateMode
            upstream = $upstreamRef
            branch_url = $branchUrl
            pr_url = $prUrl
            github_cli = $ghAvailable
            push_output = @($pushResult.Output)
            quality_gates = @($validationSuite.Results | ForEach-Object {
                [PSCustomObject]@{
                    command = $_.Command
                    success = $_.Success
                    exit_code = $_.ExitCode
                }
            })
        })
        return
    }

    Write-Section 'Next'
    Write-InfoLine "Branch URL: $branchUrl"
    Write-InfoLine "PR URL: $prUrl"

    if ($dryRun) {
        return
    }

    if ($openPrAfterPush) {
        $openResult = Open-ToiPullRequest -FallbackUrl $prUrl
        Write-InfoLine "Open method: $($openResult.Method)"
    }
    elseif ($openAfterPush) {
        Start-Process $branchUrl | Out-Null
    }
}
