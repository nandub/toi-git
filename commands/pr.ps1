function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not (Test-GitHubCliAvailable)) {
        throw 'gh.exe is not available on PATH.'
    }

    if ($Arguments.Count -eq 0) {
        throw 'Usage: .\\toi.ps1 pr <status|checks|ready|merge> [args]'
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
        throw 'Usage: .\\toi.ps1 pr <status|checks|ready|merge> [args]'
    }

    $action = $filteredArguments[0].ToLowerInvariant()
    $currentBranch = Get-CurrentBranchName

    switch ($action) {
        'status' {
            $pr = Get-ToiPullRequestInfo

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
            Write-KeyValue 'Branch' "$($pr.headRefName) -> $($pr.baseRefName)"
            Write-KeyValue 'URL' $pr.url
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
        default {
            throw 'Usage: .\\toi.ps1 pr <status|checks|ready|merge> [args]'
        }
    }
}
