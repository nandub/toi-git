function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $branch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName
    $defaultCompareRef = Get-DefaultBranchComparisonRef
    $status = Get-StatusSummary
    $upstreamRef = Get-UpstreamRef
    $isPublished = Test-CurrentBranchPublished
    $protectedBranches = Get-ProtectedBranches
    $blockingIssues = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]

    Write-Section 'Ship'
    Write-Host "Branch: $branch"
    Write-Host "Published: $isPublished"

    if ($protectedBranches -contains $branch) {
        $blockingIssues.Add("Refusing to ship directly from protected branch '$branch'.")
    }

    if ($status.Unstaged -gt 0 -or $status.Untracked -gt 0) {
        $blockingIssues.Add('Working tree is not clean enough for shipping.')
        $notes.Add('Use `.\toi.ps1 save` or commit/stage intentionally first.')
    }

    if (-not (Test-MatchesBranchConvention -BranchName $branch) -and $protectedBranches -notcontains $branch) {
        $notes.Add('Branch name is outside TOI conventions.')
    }

    if ($branch -ne $defaultBranch -and $defaultCompareRef) {
        $defaultTracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $defaultCompareRef
        if ($defaultTracking -and $defaultTracking.RightAhead -gt 0) {
            $blockingIssues.Add("Branch is behind $defaultBranch by $($defaultTracking.RightAhead) commit(s).")
        }

        $range = Get-CommitRangeSummary -BaseRef $defaultCompareRef -HeadRef 'HEAD'
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

            if ($tracking.LeftAhead -eq 0 -and $tracking.RightAhead -eq 0 -and $branch -ne $defaultBranch) {
                $notes.Add('No local commits to push.')
            }

            if ($tracking.LeftAhead -gt 0 -and $branch -ne $defaultBranch) {
                $notes.Add('Branch has local commits ready to push or review.')
            }
        }
    }
    else {
        if ($branch -eq $defaultBranch) {
            $notes.Add('Default branch has no upstream configured.')
        }
        else {
            $notes.Add('Branch is local only. Run `.\toi.ps1 publish` to push it and set upstream.')
        }
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
