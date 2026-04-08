function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $sections = Get-DashboardSections
    $branch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName
    $upstreamRef = Get-UpstreamRef
    $published = Test-CurrentBranchPublished
    $status = Get-StatusSummary
    $parent = Get-ToiStackParent -BranchName $branch
    $validationSuite = Invoke-ToiValidationSuite
    $nextActions = New-Object System.Collections.Generic.List[string]

    if ($status.Unstaged -gt 0 -or $status.Untracked -gt 0) {
        $nextActions.Add('Clean up or checkpoint the working tree with `.\toi.ps1 save`.')
    }

    if ($branch -ne $defaultBranch -and -not $published) {
        $nextActions.Add('Publish the branch with `.\toi.ps1 publish` when it is ready.')
    }

    if ($branch -ne $defaultBranch -and $published) {
        $nextActions.Add('Open the PR path with `.\toi.ps1 open pr`.')
    }

    if ($branch -eq $defaultBranch -and $status.ChangedFiles -eq 0) {
        $nextActions.Add('Create a typed branch with `.\toi.ps1 start feature <name>` for the next change.')
    }

    if ($sections -contains 'branch') {
        Write-Section 'Branch'
        Write-Host "Current: $branch"
        Write-Host "Default: $defaultBranch"
        Write-Host "Published: $published"
        Write-Host "Working tree: $($status.ChangedFiles) changed file(s)"
    }

    if ($sections -contains 'publish') {
        Write-Section 'Publish'
        if ($upstreamRef) {
            $tracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $upstreamRef
            Write-Host "Upstream: $upstreamRef"
            if ($tracking) {
                Write-Host "Ahead: $($tracking.LeftAhead)"
                Write-Host "Behind: $($tracking.RightAhead)"
            }
        }
        else {
            Write-InfoLine 'No upstream configured for the current branch.'
        }
    }

    if ($sections -contains 'stack') {
        Write-Section 'Stack'
        if ($parent) {
            Write-Host "Parent: $parent"
        }
        else {
            Write-InfoLine 'No explicit stack parent.'
        }
    }

    if ($sections -contains 'gates') {
        Write-Section 'Quality Gates'
        Write-Host "Mode: $(Get-QualityGateMode)"
        if ($validationSuite.HasChecks) {
            foreach ($result in $validationSuite.Results) {
                if ($result.Success) {
                    Write-SuccessLine "PASS  $($result.Command)"
                }
                else {
                    Write-WarningLine "FAIL  $($result.Command)"
                }
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
            $nextActions | Select-Object -Unique | ForEach-Object { Write-Host "- $_" }
        }
    }
}
