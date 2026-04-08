function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $snapshot = Get-ToiWorkflowSnapshot

    Write-Section 'Next'

    if ($snapshot.Status.Unstaged -gt 0 -or $snapshot.Status.Untracked -gt 0) {
        Write-InfoLine 'Checkpoint or clean the working tree with `.\toi.ps1 save`.'
        return
    }

    if ($snapshot.Branch -eq $snapshot.DefaultBranch) {
        Write-InfoLine 'Create a typed branch with `.\toi.ps1 start feature <name>`.'
        return
    }

    if ($snapshot.RequireBranchNote -and -not $snapshot.Note) {
        Write-InfoLine 'Add a branch note with `.\toi.ps1 note set <text>`.'
        return
    }

    if (-not $snapshot.Published) {
        Write-InfoLine 'Publish the branch with `.\toi.ps1 publish`.'
        return
    }

    if ($snapshot.UpstreamTracking -and $snapshot.UpstreamTracking.RightAhead -gt 0) {
        Write-InfoLine 'Sync the branch with `.\toi.ps1 sync`.'
        return
    }

    if ($snapshot.DefaultTracking -and $snapshot.DefaultTracking.RightAhead -gt 0) {
        Write-InfoLine "Restack or rebase onto $($snapshot.DefaultBranch) before opening the PR."
        return
    }

    if ($snapshot.StackParent) {
        Write-InfoLine 'Open the PR path with `.\toi.ps1 open pr` or restack with `.\toi.ps1 stack restack` if needed.'
        return
    }

    Write-InfoLine 'Open the PR path with `.\toi.ps1 open pr`.'
}
