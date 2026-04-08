function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not (Test-GitHubCliAvailable)) {
        throw 'gh.exe is not available on PATH.'
    }

    if (-not (Test-GitHubCliAuthenticated)) {
        throw 'gh.exe is not authenticated. Run `gh auth login` first.'
    }

    $json = $Arguments -contains '-Json'
    $review = Get-ToiPullRequestReviewSummary

    if ($json) {
        Write-Json $review
        return
    }

    Write-Section 'Review'
    Write-KeyValue 'Title' $review.title
    Write-KeyValue 'Branch' $review.branch
    Write-KeyValue 'Review' $review.review_decision
    Write-KeyValue 'Approvals' $review.reviews.approved
    Write-KeyValue 'Changes Requested' $review.reviews.changes_requested
    Write-KeyValue 'Comments' $review.reviews.commented
    Write-KeyValue 'Requested' $review.requested_reviewers.Count
    Write-KeyValue 'Ready' $review.ready
    Write-KeyValue 'Next' $review.recommended_action
    Write-KeyValue 'Command' $review.recommended_command
    Write-KeyValue 'URL' $review.url

    if ($review.requested_reviewers.Count -gt 0) {
        Write-Section 'Requested Reviewers'
        $review.requested_reviewers | ForEach-Object { Write-BulletLine $_ }
    }

    if ($review.latest_reviews.Count -gt 0) {
        Write-Section 'Latest Reviews'
        foreach ($item in $review.latest_reviews) {
            Write-BulletLine "$($item.reviewer): $($item.state)"
        }
    }

    if ($review.blockers.Count -gt 0) {
        Write-Section 'Blockers'
        $review.blockers | ForEach-Object { Write-BulletLine $_ }
    }

    if ($review.warnings.Count -gt 0) {
        Write-Section 'Warnings'
        $review.warnings | ForEach-Object { Write-BulletLine $_ }
    }
}
