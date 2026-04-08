function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $snapshot = Get-ToiWorkflowSnapshot
    $message = $null

    if ($snapshot.Status.Unstaged -gt 0 -or $snapshot.Status.Untracked -gt 0) {
        $message = 'Checkpoint or clean the working tree with `.\\toi.ps1 save`.'
    }
    elseif ($snapshot.Branch -eq $snapshot.DefaultBranch) {
        $message = 'Create a typed branch with `toi start feature <name>`.'
    }
    elseif ($snapshot.RequireBranchNote -and -not $snapshot.Note) {
        $message = 'Add a branch note with `.\\toi.ps1 note set <text>`.'
    }
    elseif (-not $snapshot.Published) {
        $message = 'Publish the branch with `.\\toi.ps1 publish`.'
    }
    elseif ($snapshot.UpstreamTracking -and $snapshot.UpstreamTracking.RightAhead -gt 0) {
        $message = 'Sync the branch with `.\\toi.ps1 sync`.'
    }
    elseif ($snapshot.DefaultTracking -and $snapshot.DefaultTracking.RightAhead -gt 0) {
        $message = "Restack or rebase onto $($snapshot.DefaultBranch) before opening the PR."
    }
    elseif (-not $snapshot.ContractStatus.SnapshotMatches) {
        $message = 'Refresh the committed contract snapshot with `.\\toi.ps1 schema -WriteSnapshot`.'
    }
    elseif ($snapshot.PullRequestGate -and $snapshot.PullRequestGate.recommended_command) {
        $message = "PR next step: $($snapshot.PullRequestGate.recommended_command)"
    }
    elseif ($snapshot.StackParent) {
        $message = 'Open the PR path with `.\\toi.ps1 open pr` or restack with `.\\toi.ps1 stack restack` if needed.'
    }
    else {
        $message = 'Open the PR path with `.\\toi.ps1 open pr`.'
    }

    if ($json) {
        Write-Json ([PSCustomObject]@{
            branch = $snapshot.Branch
            message = $message
            published = $snapshot.Published
            contract_version = $snapshot.ContractStatus.Version
            contract_snapshot_matches = $snapshot.ContractStatus.SnapshotMatches
        })
        return
    }

    Write-Section 'Next'
    Write-InfoLine $message
}

