function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $snapshot = Get-ToiWorkflowSnapshot
    $recommendations = Get-ToiDoctorRecommendations -Snapshot $snapshot

    if ($json) {
        $model = Convert-ToiSnapshotToJsonModel -Snapshot $snapshot
        $model | Add-Member -NotePropertyName recommendations -NotePropertyValue @($recommendations) -Force
        Write-Json $model
        return
    }

    Write-Section 'Doctor'
    Write-Host "Branch: $($snapshot.Branch)"
    Write-Host "Default branch: $($snapshot.DefaultBranch)"
    Write-Host "Sync strategy: $(Get-SyncStrategy)"
    Write-Host "Working tree: $($snapshot.Status.ChangedFiles) changed file(s)"
    Write-Host "Published: $($snapshot.Published)"
    Write-Host "Commit convention: $($snapshot.CommitConvention)"
    if ($snapshot.Note) {
        Write-Host "Note: $($snapshot.Note)"
    }

    if ($snapshot.Status.Staged -gt 0) {
        Write-Host "Staged entries: $($snapshot.Status.Staged)"
    }

    if ($snapshot.Status.Unstaged -gt 0) {
        Write-Host "Unstaged entries: $($snapshot.Status.Unstaged)"
    }

    if ($snapshot.Status.Untracked -gt 0) {
        Write-Host "Untracked entries: $($snapshot.Status.Untracked)"
    }

    if (Test-MatchesBranchConvention -BranchName $snapshot.Branch) {
        Write-SuccessLine 'Branch name matches TOI conventions.'
    }
    elseif ($snapshot.ProtectedBranches -notcontains $snapshot.Branch) {
        Write-WarningLine 'Branch name does not match configured TOI branch types.'
    }

    if ($snapshot.UpstreamRef) {
        Write-Host "Upstream: $($snapshot.UpstreamRef)"
        if ($snapshot.UpstreamTracking) {
            Write-Host "Ahead of upstream: $($snapshot.UpstreamTracking.LeftAhead)"
            Write-Host "Behind upstream: $($snapshot.UpstreamTracking.RightAhead)"
        }
    }
    else {
        Write-WarningLine 'Current branch has no upstream.'
    }

    if ($snapshot.DefaultTracking -and $snapshot.DefaultTracking.RightAhead -gt 0) {
        Write-WarningLine "Branch is behind $($snapshot.DefaultBranch) by $($snapshot.DefaultTracking.RightAhead) commit(s)."
    }

    Write-Section 'Next Actions'
    if ($recommendations.Count -eq 0) {
        Write-SuccessLine 'No obvious workflow issues detected.'
        Write-InfoLine 'Likely next step: `toi ship`'
        return
    }

    $recommendations | ForEach-Object { Write-Host "- $_" }
}

