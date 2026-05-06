function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $snapshot = Get-ToiWorkflowSnapshot
    $assessment = Get-ToiShipAssessment -Snapshot $snapshot
    $commitRange = if ($snapshot.Branch -ne $snapshot.DefaultBranch -and (Get-DefaultBranchComparisonRef)) {
        Get-CommitRangeSummary -BaseRef (Get-DefaultBranchComparisonRef) -HeadRef 'HEAD'
    }
    else {
        @()
    }

    if ($json) {
        $model = Convert-ToiSnapshotToJsonModel -Snapshot $snapshot
        $model | Add-Member -NotePropertyName ship -NotePropertyValue ([PSCustomObject]@{
            blocking_issues = @($assessment.blocking_issues)
            notes = @($assessment.notes)
            commit_range = @($commitRange)
            shippable = (@($assessment.blocking_issues).Count -eq 0)
        }) -Force
        Write-Json $model
        return
    }

    Write-Section 'Ship'
    Write-Host "Branch: $($snapshot.Branch)"
    Write-Host "Published: $($snapshot.Published)"
    Write-Host "Quality gate mode: $($assessment.quality_gate_mode)"

    if ($snapshot.Branch -ne $snapshot.DefaultBranch) {
        Write-Section 'Commits Since Base'
        if (@($commitRange).Count -eq 0) {
            Write-InfoLine 'No commits ahead of the default branch.'
        }
        else {
            $commitRange | Select-Object -First 10 | ForEach-Object { Write-Host $_ }
        }
    }

    if ($snapshot.UpstreamTracking) {
        Write-Section 'Upstream'
        Write-Host "Ahead: $($snapshot.UpstreamTracking.LeftAhead)"
        Write-Host "Behind: $($snapshot.UpstreamTracking.RightAhead)"
    }

    if ($snapshot.ValidationSuite.HasChecks) {
        Write-Section 'Quality Gates'
        foreach ($result in $snapshot.ValidationSuite.Results) {
            if ($result.Success) {
                Write-SuccessLine "PASS  $($result.Command)"
            }
            else {
                if ($assessment.quality_gate_mode -eq 'block') {
                    Write-ErrorLine "FAIL  $($result.Command)"
                }
                else {
                    Write-WarningLine "WARN  $($result.Command)"
                }
            }

            $result.Output | Select-Object -First 5 | ForEach-Object { Write-InfoLine "  $_" }
        }
    }
    else {
        Write-Section 'Quality Gates'
        Write-InfoLine 'No validation commands configured.'
    }

    Write-Section 'Assessment'
    if (@($assessment.blocking_issues).Count -gt 0) {
        $assessment.blocking_issues | ForEach-Object { Write-ErrorLine $_ }
    }
    else {
        Write-SuccessLine 'Branch looks shippable.'
    }

    if (@($assessment.notes).Count -gt 0) {
        $assessment.notes | ForEach-Object { Write-Host "- $_" }
    }
}
