function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $branch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName
    $status = Get-StatusSummary
    $upstreamRef = Get-UpstreamRef
    $protectedBranches = Get-ProtectedBranches
    $blockingIssues = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]

    Write-Section 'Ship'
    Write-Host "Branch: $branch"

    if ($protectedBranches -contains $branch) {
        $blockingIssues.Add("Refusing to ship directly from protected branch '$branch'.")
    }

    if ($status.Unstaged -gt 0 -or $status.Untracked -gt 0) {
        $blockingIssues.Add('Working tree is not clean enough for shipping.')
        $notes.Add('Use `.\toi.ps1 save` or commit/stage intentionally first.')
    }

    if ($branch -notmatch '^(feature|fix|hotfix|release|chore)/') {
        $notes.Add('Branch name is outside TOI conventions.')
    }

    if ($branch -ne $defaultBranch -and (Test-RefExists -RefName "refs/heads/$defaultBranch")) {
        $defaultTracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $defaultBranch
        if ($defaultTracking -and $defaultTracking.RightAhead -gt 0) {
            $notes.Add("Branch is behind $defaultBranch by $($defaultTracking.RightAhead) commit(s).")
        }

        $range = Get-CommitRangeSummary -BaseRef $defaultBranch -HeadRef 'HEAD'
        Write-Section 'Commits Since Base'
        if ($range.Count -eq 0) {
            Write-InfoLine 'No commits ahead of the default branch.'
        }
        else {
            $range | Select-Object -First 10 | ForEach-Object { Write-Host $_ }
        }
    }

    if ($upstreamRef) {
        $tracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $upstreamRef
        if ($tracking) {
            Write-Section 'Upstream'
            Write-Host "Ahead: $($tracking.LeftAhead)"
            Write-Host "Behind: $($tracking.RightAhead)"

            if ($tracking.RightAhead -gt 0) {
                $blockingIssues.Add('Branch is behind its upstream.')
            }

            if ($tracking.LeftAhead -eq 0 -and $tracking.RightAhead -eq 0) {
                $notes.Add('No local commits to push.')
            }
        }
    }
    else {
        $notes.Add('No upstream configured yet. First push should use `git push -u origin <branch>`.')
    }

    Write-Section 'Assessment'
    if ($blockingIssues.Count -gt 0) {
        $blockingIssues | ForEach-Object { Write-ErrorLine $_ }
    }
    else {
        Write-SuccessLine 'Branch looks shippable.'
    }

    if ($notes.Count -gt 0) {
        $notes | Select-Object -Unique | ForEach-Object { Write-Host "- $_" }
    }
}
