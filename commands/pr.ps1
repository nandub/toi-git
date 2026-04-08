function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not (Test-GitHubCliAvailable)) {
        throw 'gh.exe is not available on PATH.'
    }

    if ($Arguments.Count -eq 0) {
        throw 'Usage: .\\toi.ps1 pr <status|checks|ready|merge|gate> [args]'
    }

    $json = $Arguments -contains '-Json'
    $dryRun = $Arguments -contains '-DryRun'
    $required = $Arguments -contains '-Required'
    $undo = $Arguments -contains '-Undo'
    $deleteBranch = $Arguments -contains '-DeleteBranch'
    $auto = $Arguments -contains '-Auto'
    $admin = $Arguments -contains '-Admin'
    $mergeStrategy = 'squash'
    if ($Arguments -contains '-Merge') {
        $mergeStrategy = 'merge'
    }
    elseif ($Arguments -contains '-Rebase') {
        $mergeStrategy = 'rebase'
    }
    elseif ($Arguments -contains '-Squash') {
        $mergeStrategy = 'squash'
    }
    $filteredArguments = @($Arguments | Where-Object { $_ -notin @('-Json', '-DryRun', '-Required', '-Undo', '-DeleteBranch', '-Auto', '-Admin', '-Merge', '-Rebase', '-Squash') })

    if ($filteredArguments.Count -eq 0) {
        throw 'Usage: .\\toi.ps1 pr <status|checks|ready|merge|gate> [args]'
    }

    $action = $filteredArguments[0].ToLowerInvariant()
    $currentBranch = Get-CurrentBranchName

    switch ($action) {
        'status' {
            $pr = Get-ToiPullRequestInfo
            $requestedReviewers = @(Get-ToiPullRequestRequestedReviewers -PullRequest $pr)
            $reviewSummary = Get-ToiPullRequestLatestReviewSummary -PullRequest $pr

            if ($json) {
                Write-Json $pr
                return
            }

            Write-Section 'PR Status'
            Write-KeyValue 'Number' $pr.number
            Write-KeyValue 'Title' $pr.title
            Write-KeyValue 'State' $pr.state
            Write-KeyValue 'Draft' $pr.isDraft
            Write-KeyValue 'Review' $pr.reviewDecision
            Write-KeyValue 'Merge State' $pr.mergeStateStatus
            Write-KeyValue 'Approvals' $reviewSummary.approved
            Write-KeyValue 'Review Requests' $requestedReviewers.Count
            Write-KeyValue 'Branch' "$($pr.headRefName) -> $($pr.baseRefName)"
            Write-KeyValue 'URL' $pr.url
            if ($requestedReviewers.Count -gt 0) {
                Write-Section 'Requested Reviewers'
                $requestedReviewers | ForEach-Object { Write-BulletLine $_ }
            }
        }
        'checks' {
            $checks = @(Get-ToiPullRequestChecks -Required:$required)
            $summary = Get-ToiPullRequestChecksSummary -Checks $checks

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    branch = $currentBranch
                    required = $required
                    summary = $summary
                    checks = @($checks)
                })
                return
            }

            Write-Section 'PR Checks'
            Write-KeyValue 'Branch' $currentBranch
            Write-KeyValue 'Required' $required
            Write-KeyValue 'Pass' $summary.pass
            Write-KeyValue 'Fail' $summary.fail
            Write-KeyValue 'Pending' $summary.pending
            Write-KeyValue 'Cancel' $summary.cancel
            Write-KeyValue 'Skip' $summary.skipping

            foreach ($check in $checks) {
                $tone = switch ($check.bucket) {
                    'pass' { 'good' }
                    'fail' { 'bad' }
                    'pending' { 'warn' }
                    'cancel' { 'warn' }
                    default { 'neutral' }
                }

                Write-StatusBadge -Label ($check.bucket.ToUpperInvariant()) -Tone $tone
                Write-Host " $($check.name)"
                if ($check.workflow) {
                    Write-InfoLine "  Workflow: $($check.workflow)"
                }
                if ($check.state) {
                    Write-InfoLine "  State: $($check.state)"
                }
                if ($check.link) {
                    Write-InfoLine "  Link: $($check.link)"
                }
            }
        }
        'ready' {
            $result = Set-ToiPullRequestReady -Undo:$undo -DryRun:$dryRun

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    branch = $currentBranch
                    dry_run = $dryRun
                    undo = $undo
                    command = @($result.Command)
                    output = @($result.Output)
                })
                return
            }

            Write-Section 'PR Ready'
            Write-KeyValue 'Branch' $currentBranch
            Write-KeyValue 'Dry Run' $dryRun
            Write-KeyValue 'Undo' $undo
            if ($dryRun) {
                Write-InfoLine ("gh " + ($result.Command -join ' '))
                return
            }

            $result.Output | ForEach-Object { Write-Host $_ }
        }
        'merge' {
            $result = Merge-ToiPullRequest -Strategy $mergeStrategy -DeleteBranch:$deleteBranch -Auto:$auto -Admin:$admin -DryRun:$dryRun

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    branch = $currentBranch
                    dry_run = $dryRun
                    strategy = $mergeStrategy
                    auto = $auto
                    admin = $admin
                    delete_branch = $deleteBranch
                    command = @($result.Command)
                    output = @($result.Output)
                })
                return
            }

            Write-Section 'PR Merge'
            Write-KeyValue 'Branch' $currentBranch
            Write-KeyValue 'Dry Run' $dryRun
            Write-KeyValue 'Strategy' $mergeStrategy
            Write-KeyValue 'Auto' $auto
            Write-KeyValue 'Admin' $admin
            Write-KeyValue 'Delete Branch' $deleteBranch
            if ($dryRun) {
                Write-InfoLine ("gh " + ($result.Command -join ' '))
                return
            }

            $result.Output | ForEach-Object { Write-Host $_ }
        }
        'gate' {
            $gate = Get-ToiPullRequestGateStatus

            if ($json) {
                Write-Json $gate
                return
            }

            Write-Section 'PR Gate'
            if ($gate.ready) {
                Write-StatusBadge -Label 'READY' -Tone 'good'
            }
            else {
                Write-StatusBadge -Label 'BLOCKED' -Tone 'bad'
            }
            Write-Host " $($gate.title)"
            Write-KeyValue 'Branch' $gate.branch
            Write-KeyValue 'URL' $gate.url
            Write-KeyValue 'Draft' $gate.draft
            Write-KeyValue 'Review' $gate.review_decision
            Write-KeyValue 'Merge State' $gate.merge_state
            Write-KeyValue 'Approvals' $gate.reviews.approved
            Write-KeyValue 'Review Requests' $gate.requested_reviewers.Count
            Write-KeyValue 'Required Pass' $gate.checks.pass
            Write-KeyValue 'Required Fail' $gate.checks.fail
            Write-KeyValue 'Required Pending' $gate.checks.pending

            if ($gate.requested_reviewers.Count -gt 0) {
                Write-Section 'Requested Reviewers'
                $gate.requested_reviewers | ForEach-Object { Write-BulletLine $_ }
            }

            if ($gate.blockers.Count -gt 0) {
                Write-Section 'Blockers'
                $gate.blockers | ForEach-Object { Write-BulletLine $_ }
            }

            if ($gate.warnings.Count -gt 0) {
                Write-Section 'Warnings'
                $gate.warnings | ForEach-Object { Write-BulletLine $_ }
            }
        }
        default {
            throw 'Usage: .\\toi.ps1 pr <status|checks|ready|merge|gate> [args]'
        }
    }
}
