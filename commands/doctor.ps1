function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $branch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName
    $upstreamRef = Get-UpstreamRef
    $status = Get-StatusSummary
    $protectedBranches = Get-ProtectedBranches
    $recommendations = New-Object System.Collections.Generic.List[string]

    Write-Section 'Doctor'
    Write-Host "Branch: $branch"
    Write-Host "Default branch: $defaultBranch"
    Write-Host "Sync strategy: $(Get-SyncStrategy)"
    Write-Host "Working tree: $($status.ChangedFiles) changed file(s)"

    if ($status.Staged -gt 0) {
        Write-Host "Staged entries: $($status.Staged)"
    }

    if ($status.Unstaged -gt 0) {
        Write-Host "Unstaged entries: $($status.Unstaged)"
    }

    if ($status.Untracked -gt 0) {
        Write-Host "Untracked entries: $($status.Untracked)"
    }

    if ($branch -match '^(feature|fix|hotfix|release|chore)/') {
        Write-SuccessLine 'Branch name matches TOI conventions.'
    }
    elseif ($protectedBranches -notcontains $branch) {
        Write-WarningLine 'Branch name does not match configured TOI branch types.'
        $recommendations.Add('Consider creating a typed branch with `.\toi.ps1 start <type> <name>`.')
    }

    if ($protectedBranches -contains $branch -and -not (Test-WorkingTreeClean)) {
        $recommendations.Add("Avoid doing feature work directly on '$branch'. Create a branch with `.\toi.ps1 start feature <name>`.")
    }

    if ($upstreamRef) {
        Write-Host "Upstream: $upstreamRef"
        $tracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $upstreamRef
        if ($tracking) {
            Write-Host "Ahead of upstream: $($tracking.LeftAhead)"
            Write-Host "Behind upstream: $($tracking.RightAhead)"

            if ($tracking.RightAhead -gt 0) {
                $recommendations.Add('Run `.\toi.ps1 sync` before pushing or opening a PR.')
            }

            if ($tracking.LeftAhead -gt 0) {
                $recommendations.Add('Branch has local commits ready to push or review.')
            }
        }
    }
    else {
        Write-WarningLine 'Current branch has no upstream.'
        $recommendations.Add('Push with `git push -u origin <branch>` when this branch is ready.')
    }

    if ($branch -ne $defaultBranch -and (Test-RefExists -RefName "refs/heads/$defaultBranch")) {
        $defaultTracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $defaultBranch
        if ($defaultTracking -and $defaultTracking.RightAhead -gt 0) {
            Write-WarningLine "Branch is behind $defaultBranch by $($defaultTracking.RightAhead) commit(s)."
            $recommendations.Add('Rebase or sync against the default branch before shipping.')
        }
    }

    Write-Section 'Next Actions'
    if ($recommendations.Count -eq 0) {
        Write-SuccessLine 'No obvious workflow issues detected.'
        Write-InfoLine 'Likely next step: `.\toi.ps1 ship`'
        return
    }

    $recommendations | Select-Object -Unique | ForEach-Object { Write-Host "- $_" }
}
