function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $sections = Get-DashboardSections
    $snapshot = Get-ToiWorkflowSnapshot
    $nextActions = New-Object System.Collections.Generic.List[string]

    if ($snapshot.Status.Unstaged -gt 0 -or $snapshot.Status.Untracked -gt 0) {
        $nextActions.Add('Clean up or checkpoint the working tree with `.\toi.ps1 save`.')
    }

    if ($snapshot.Branch -ne $snapshot.DefaultBranch -and -not $snapshot.Published) {
        $nextActions.Add('Publish the branch with `.\toi.ps1 publish` when it is ready.')
    }

    if ($snapshot.Branch -ne $snapshot.DefaultBranch -and $snapshot.Published) {
        $nextActions.Add('Open the PR path with `.\toi.ps1 open pr`.')
    }

    if ($snapshot.Branch -eq $snapshot.DefaultBranch -and $snapshot.Status.ChangedFiles -eq 0) {
        $nextActions.Add('Create a typed branch with `.\toi.ps1 start feature <name>` for the next change.')
    }

    if ($snapshot.RequireBranchNote -and $snapshot.Branch -ne $snapshot.DefaultBranch -and -not $snapshot.Note) {
        $nextActions.Add('Add a branch note with `.\toi.ps1 note set <text>`.')
    }

    if ($snapshot.UpstreamTracking -and $snapshot.UpstreamTracking.RightAhead -gt 0) {
        $nextActions.Add('Sync the branch with `.\toi.ps1 sync` before pushing or opening a PR.')
    }

    if ($snapshot.DefaultTracking -and $snapshot.DefaultTracking.RightAhead -gt 0) {
        $nextActions.Add("Restack or rebase on $($snapshot.DefaultBranch) to pick up newer commits.")
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

    if ($sections -contains 'next') {
        Write-Section 'Next'
        if ($nextActions.Count -eq 0) {
            Write-InfoLine 'No obvious next step.'
        }
        else {
            $nextActions | Select-Object -Unique | ForEach-Object { Write-BulletLine $_ }
        }
    }
}
