function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $sections = Get-DashboardSections
    $snapshot = Get-ToiWorkflowSnapshot
    $nextActions = Get-ToiNextActions -Snapshot $snapshot

    if ($json) {
        $model = Convert-ToiSnapshotToJsonModel -Snapshot $snapshot
        $model | Add-Member -NotePropertyName next_actions -NotePropertyValue @($nextActions) -Force
        Write-Json $model
        return
    }

    if ($sections -contains 'branch') {
        Write-Section 'Branch'
        Write-KeyValue 'Current' $snapshot.Branch
        Write-KeyValue 'Default' $snapshot.DefaultBranch
        Write-KeyValue 'Type' $(if ($snapshot.BranchType) { $snapshot.BranchType } else { 'n/a' })
        Write-KeyValue 'Published' $snapshot.Published
        Write-KeyValue 'Working tree' "$($snapshot.Status.ChangedFiles) changed file(s)"
        Write-KeyValue 'Commit style' $snapshot.CommitConvention
        if ($snapshot.Note) {
            Write-KeyValue 'Note' $snapshot.Note
        }
    }

    if ($sections -contains 'publish') {
        Write-Section 'Publish'
        if ($snapshot.UpstreamRef) {
            Write-KeyValue 'Upstream' $snapshot.UpstreamRef
            if ($snapshot.UpstreamTracking) {
                Write-KeyValue 'Ahead' $snapshot.UpstreamTracking.LeftAhead
                Write-KeyValue 'Behind' $snapshot.UpstreamTracking.RightAhead
            }
        }
        else {
            Write-InfoLine 'No upstream configured for the current branch.'
        }
    }

    if ($sections -contains 'stack') {
        Write-Section 'Stack'
        if ($snapshot.StackParent) {
            Write-KeyValue 'Parent' $snapshot.StackParent
        }
        else {
            Write-InfoLine 'No explicit stack parent.'
        }

        if ($snapshot.DefaultTracking) {
            Write-KeyValue "Behind $($snapshot.DefaultBranch)" $snapshot.DefaultTracking.RightAhead
        }
    }

    if ($sections -contains 'pr' -and $snapshot.PullRequestGate) {
        Write-Section 'Pull Request'
        if ($snapshot.PullRequestGate.ready) {
            Write-KeyValue 'Ready' 'True'
        }
        else {
            Write-KeyValue 'Ready' 'False'
        }
        Write-KeyValue 'Review' $snapshot.PullRequestGate.review_decision
        Write-KeyValue 'Merge State' $snapshot.PullRequestGate.merge_state
        Write-KeyValue 'Approvals' $snapshot.PullRequestGate.reviews.approved
        Write-KeyValue 'Requests' $snapshot.PullRequestGate.requested_reviewers.Count
        Write-KeyValue 'Next' $snapshot.PullRequestGate.recommended_action
        Write-KeyValue 'Command' $snapshot.PullRequestGate.recommended_command
    }

    if ($sections -contains 'gates') {
        Write-Section 'Quality Gates'
        Write-KeyValue 'Mode' (Get-QualityGateMode)
        if ($snapshot.ValidationSuite.HasChecks) {
            foreach ($result in $snapshot.ValidationSuite.Results) {
                if ($result.Success) {
                    Write-StatusBadge -Label 'PASS' -Tone 'good'
                }
                else {
                    Write-StatusBadge -Label 'FAIL' -Tone 'warn'
                }
                Write-Host " $($result.Command)"
            }
        }
        else {
            Write-InfoLine 'No validation commands configured.'
        }
    }

    if ($sections -contains 'contract') {
        Write-Section 'Contracts'
        Write-KeyValue 'Version' $snapshot.ContractStatus.Version
        Write-KeyValue 'Snapshot' $snapshot.ContractStatus.SnapshotMatches
        Write-InfoLine $snapshot.ContractStatus.Reason
    }

    if ($sections -contains 'next') {
        Write-Section 'Next'
        if ($nextActions.Count -eq 0) {
            Write-InfoLine 'No obvious next step.'
        }
        else {
            $nextActions | ForEach-Object { Write-BulletLine $_ }
        }
    }
}
