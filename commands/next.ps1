function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $branch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName
    $published = Test-CurrentBranchPublished
    $status = Get-StatusSummary
    $upstreamRef = Get-UpstreamRef
    $parent = Get-ToiStackParent -BranchName $branch
    $note = Get-ToiBranchNote -BranchName $branch

    Write-Section 'Next'

    if ($status.Unstaged -gt 0 -or $status.Untracked -gt 0) {
        Write-InfoLine 'Checkpoint or clean the working tree with `.\toi.ps1 save`.'
        return
    }

    if ($branch -eq $defaultBranch) {
        Write-InfoLine 'Create a typed branch with `.\toi.ps1 start feature <name>`.'
        return
    }

    if ((Test-BranchNoteRequired) -and -not $note) {
        Write-InfoLine 'Add a branch note with `.\toi.ps1 note set <text>`.'
        return
    }

    if (-not $published) {
        Write-InfoLine 'Publish the branch with `.\toi.ps1 publish`.'
        return
    }

    if ($upstreamRef) {
        $tracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $upstreamRef
        if ($tracking -and $tracking.RightAhead -gt 0) {
            Write-InfoLine 'Sync the branch with `.\toi.ps1 sync`.'
            return
        }
    }

    if ($parent) {
        Write-InfoLine 'Open the PR path with `.\toi.ps1 open pr` or restack with `.\toi.ps1 stack restack` if needed.'
        return
    }

    Write-InfoLine 'Open the PR path with `.\toi.ps1 open pr`.'
}
