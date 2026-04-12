function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $push = $Arguments -contains '-Push'
    $dryRun = $Arguments -contains '-DryRun'
    $branch = Get-CurrentBranchName
    $repositoryState = Get-ToiRepositoryState
    $upstreamRef = Get-UpstreamRef
    $syncStrategy = Get-SyncStrategy
    $defaultBranch = Get-DefaultBranchName
    $remoteDefaultRef = Get-RemoteDefaultBranchRef
    $protectedBranches = Get-ProtectedBranches

    if ($push -and ($protectedBranches -contains $branch)) {
        if ($json) {
            Write-Json ([PSCustomObject]@{
                blocked = $true
                reason = "Refusing to push from protected branch '$branch'."
                branch = $branch
                dry_run = $dryRun
            })
            return
        }

        throw "Refusing to push from protected branch '$branch'."
    }

    if ($repositoryState.blocking) {
        $blockedResult = [PSCustomObject]@{
            branch = $branch
            push = $push
            dry_run = $dryRun
            clean = Test-WorkingTreeClean
            sync_strategy = Get-SyncStrategy
            tracking_ref = $upstreamRef
            upstream = $upstreamRef
            fetched = $false
            fetch_output = @()
            fetch_reason = $repositoryState.description
            updated = $false
            update_mode = $null
            update_output = @()
            ahead = $null
            behind = $null
            pushed = $false
            push_output = @()
            push_reason = 'Sync is blocked until the current repository operation is resolved.'
            would_fetch = $null
            would_update = $null
            would_push = $null
            update_reason = $repositoryState.description
            repository_state = [PSCustomObject]@{
                state = $repositoryState.state
                description = $repositoryState.description
                recovery = @($repositoryState.recovery)
                blocking = $repositoryState.blocking
            }
        }

        if ($json) {
            Write-Json $blockedResult
            return
        }

        Write-Section 'Sync'
        Write-KeyValue 'Branch' $branch
        Write-KeyValue 'Push' $push
        Write-KeyValue 'Dry Run' $dryRun
        Write-KeyValue 'Sync Strategy' $syncStrategy
        Write-Section 'Blocked'
        Write-WarningLine $repositoryState.description
        $repositoryState.recovery | ForEach-Object { Write-Host "- $_" }
        return
    }

    $fetchResult = Invoke-GitWithTimeout -GitArguments @('fetch', '--all', '--prune') -TimeoutSeconds 20 -DisablePrompt -AllowFailure
    $fetchSucceeded = ($fetchResult.ExitCode -eq 0)
    $fetchReason = $null
    if (-not $fetchSucceeded) {
        $fetchReason = if ($fetchResult.Output.Count -gt 0) {
            $fetchResult.Output -join [Environment]::NewLine
        }
        else {
            'Fetch failed.'
        }
    }

    if ($push -and -not $fetchSucceeded -and (Test-ToiGitTransportError -Message $fetchReason)) {
        $fetchResult = Invoke-GitInteractive -GitArguments @('fetch', '--all', '--prune') -AllowFailure
        $fetchSucceeded = ($fetchResult.ExitCode -eq 0)
        $fetchReason = if ($fetchSucceeded) {
            $null
        }
        elseif ($fetchResult.Output.Count -gt 0) {
            $fetchResult.Output -join [Environment]::NewLine
        }
        else {
            'Fetch failed.'
        }
    }

    $trackingRef = $upstreamRef
    if (-not $trackingRef -and $branch -eq $defaultBranch -and $remoteDefaultRef) {
        $trackingRef = $remoteDefaultRef
    }

    $trackingAvailable = [bool]$trackingRef
    $clean = Test-WorkingTreeClean
    $preAheadBehind = if ($trackingRef) { Get-AheadBehind -LeftRef $trackingRef -RightRef 'HEAD' } else { $null }
    $plannedUpdateMode = $null
    $plannedUpdateReason = $null
    $wouldFetch = $true
    $wouldUpdate = $false
    $wouldPush = $false

    if ($trackingAvailable -and $clean) {
        if ($upstreamRef -or ($branch -eq $defaultBranch -and $remoteDefaultRef)) {
            $plannedUpdateMode = if ($syncStrategy -eq 'rebase') { 'rebase' } else { 'merge-ff-only' }
            $wouldUpdate = $true
        }
    }
    elseif (-not $clean) {
        $plannedUpdateReason = 'Working tree is not clean.'
    }
    else {
        $plannedUpdateReason = 'No upstream or remote default branch is available for local sync.'
    }

    if ($push) {
        if (-not $clean) {
            $plannedPushReason = 'Working tree is not clean. Push would be skipped.'
        }
        elseif (-not $upstreamRef) {
            $plannedPushReason = 'No upstream is configured for the current branch. Use `toi publish` to push it first.'
        }
        elseif ($preAheadBehind -and $preAheadBehind.RightAhead -gt 0) {
            $plannedPushReason = 'Branch is behind its upstream and would need to sync cleanly before push.'
        }
        elseif ($preAheadBehind -and $preAheadBehind.LeftAhead -eq 0) {
            $plannedPushReason = 'No local commits to push.'
        }
        else {
            $plannedPushReason = $null
            $wouldPush = $true
        }
    }
    else {
        $plannedPushReason = $null
    }

    if ($dryRun) {
        $result = [PSCustomObject]@{
            branch = $branch
            push = $push
            dry_run = $true
            clean = $clean
            sync_strategy = $syncStrategy
            tracking_ref = $trackingRef
            upstream = $upstreamRef
            fetched = $false
            fetch_output = @()
            fetch_reason = 'Dry run: fetch was not executed.'
            updated = $false
            update_mode = $plannedUpdateMode
            update_output = @()
            ahead = if ($preAheadBehind) { $preAheadBehind.LeftAhead } else { $null }
            behind = if ($preAheadBehind) { $preAheadBehind.RightAhead } else { $null }
            pushed = $false
            push_output = @()
            push_reason = $plannedPushReason
            would_fetch = $wouldFetch
            would_update = $wouldUpdate
            would_push = $wouldPush
            update_reason = $plannedUpdateReason
            repository_state = [PSCustomObject]@{
                state = $repositoryState.state
                description = $repositoryState.description
                recovery = @($repositoryState.recovery)
                blocking = $repositoryState.blocking
            }
        }

        if ($json) {
            Write-Json $result
            return
        }

        Write-Section 'Sync'
        Write-KeyValue 'Branch' $branch
        Write-KeyValue 'Push' $push
        Write-KeyValue 'Dry Run' $true
        Write-KeyValue 'Sync Strategy' $syncStrategy

        Write-Section 'Fetch'
        Write-InfoLine 'Would fetch remotes.'

        Write-Section 'Tracking'
        if ($trackingRef) {
            Write-KeyValue 'Compare Ref' $trackingRef
        }
        else {
            Write-InfoLine 'No upstream configured for the current branch.'
        }

        Write-Section 'Update'
        if ($wouldUpdate) {
            Write-InfoLine "Would run $plannedUpdateMode against $trackingRef."
        }
        else {
            if ($plannedUpdateReason) {
                Write-InfoLine $plannedUpdateReason
            }
            else {
                Write-InfoLine 'No local update would run.'
            }
        }

        if ($null -ne $result.ahead -or $null -ne $result.behind) {
            Write-Section 'Upstream'
            Write-KeyValue 'Ahead' $result.ahead
            Write-KeyValue 'Behind' $result.behind
        }

        if ($push) {
            Write-Section 'Push'
            if ($wouldPush) {
                Write-InfoLine 'Would push local commits after sync.'
            }
            else {
                Write-InfoLine $plannedPushReason
            }
        }

        return
    }

    $updateMode = $null
    $updateResult = [PSCustomObject]@{
        Output = @()
        ExitCode = 0
    }
    $updated = $false
    if ($fetchSucceeded -and $trackingAvailable -and $clean) {
        if ($upstreamRef -or ($branch -eq $defaultBranch -and $remoteDefaultRef)) {
            if ($syncStrategy -eq 'rebase') {
                $updateMode = 'rebase'
                $updateResult = Invoke-Git -GitArguments @('rebase', $trackingRef)
            }
            else {
                $updateMode = 'merge-ff-only'
                $updateResult = Invoke-Git -GitArguments @('merge', '--ff-only', $trackingRef)
            }
        }

        $updated = $true
    }

    $postUpstreamRef = Get-UpstreamRef
    $postTrackingRef = if ($postUpstreamRef) { $postUpstreamRef } elseif ($branch -eq $defaultBranch) { Get-RemoteDefaultBranchRef } else { $null }
    $aheadBehind = if ($postTrackingRef) { Get-AheadBehind -LeftRef $postTrackingRef -RightRef 'HEAD' } else { $null }

    $pushResult = [PSCustomObject]@{
        Output = @()
        ExitCode = 0
    }
    $pushed = $false
    $pushReason = $null

    if ($push) {
        if (-not $fetchSucceeded) {
            $pushReason = 'Fetch did not complete successfully. Push was skipped.'
        }
        elseif (-not $clean) {
            $pushReason = 'Working tree is not clean. Sync fetch completed, but push was skipped.'
        }
        elseif (-not $postUpstreamRef) {
            $pushReason = 'No upstream is configured for the current branch. Use `toi publish` to push it first.'
        }
        elseif ($aheadBehind -and $aheadBehind.RightAhead -gt 0) {
            $pushReason = 'Branch is still behind its upstream after sync. Resolve that state before pushing.'
        }
        elseif ($aheadBehind -and $aheadBehind.LeftAhead -eq 0) {
            $pushReason = 'No local commits to push after sync.'
        }
        else {
            $pushResult = Invoke-GitInteractive -GitArguments @('push')
            $pushed = $true
            $postUpstreamRef = Get-UpstreamRef
            $postTrackingRef = if ($postUpstreamRef) { $postUpstreamRef } elseif ($branch -eq $defaultBranch) { Get-RemoteDefaultBranchRef } else { $null }
            $aheadBehind = if ($postTrackingRef) { Get-AheadBehind -LeftRef $postTrackingRef -RightRef 'HEAD' } else { $null }
        }
    }

    $result = [PSCustomObject]@{
        branch = $branch
        push = $push
        dry_run = $false
        clean = $clean
        sync_strategy = $syncStrategy
        tracking_ref = $trackingRef
        upstream = $postUpstreamRef
        fetched = $fetchSucceeded
        fetch_output = @($fetchResult.Output)
        fetch_reason = $fetchReason
        updated = $updated
        update_mode = $updateMode
        update_output = @($updateResult.Output)
        ahead = if ($aheadBehind) { $aheadBehind.LeftAhead } else { $null }
        behind = if ($aheadBehind) { $aheadBehind.RightAhead } else { $null }
        pushed = $pushed
        push_output = @($pushResult.Output)
        push_reason = $pushReason
        would_fetch = $null
        would_update = $null
        would_push = $null
        update_reason = $null
        repository_state = [PSCustomObject]@{
            state = $repositoryState.state
            description = $repositoryState.description
            recovery = @($repositoryState.recovery)
            blocking = $repositoryState.blocking
        }
    }

    if ($json) {
        Write-Json $result
        return
    }

    Write-Section 'Sync'
    Write-KeyValue 'Branch' $branch
    Write-KeyValue 'Push' $push
    Write-KeyValue 'Dry Run' $false
    Write-KeyValue 'Sync Strategy' $syncStrategy

    Write-Section 'Fetch'
    if (-not $fetchSucceeded) {
        Write-WarningLine $fetchReason
    }
    elseif ($fetchResult.Output.Count -gt 0) {
        $fetchResult.Output | ForEach-Object { Write-Host $_ }
    }
    else {
        Write-SuccessLine 'Fetch completed.'
    }

    Write-Section 'Tracking'
    if ($trackingRef) {
        Write-KeyValue 'Compare Ref' $trackingRef
    }
    else {
        Write-InfoLine 'No upstream configured for the current branch.'
    }

    if (-not $fetchSucceeded) {
        Write-InfoLine 'Local branch update was skipped because fetch did not complete successfully.'
    }
    elseif (-not $clean) {
        Write-WarningLine 'Working tree is not clean. Fetch completed, but branch update was skipped.'
    }
    elseif (-not $trackingAvailable) {
        Write-InfoLine 'No upstream or remote default branch was available for local sync.'
    }
    else {
        Write-Section 'Update'
        if ($updateResult.Output.Count -gt 0) {
            $updateResult.Output | ForEach-Object { Write-Host $_ }
        }
        else {
            Write-SuccessLine 'Branch update completed.'
        }
    }

    if ($null -ne $result.ahead -or $null -ne $result.behind) {
        Write-Section 'Upstream'
        Write-KeyValue 'Ahead' $result.ahead
        Write-KeyValue 'Behind' $result.behind
    }

    if ($push) {
        Write-Section 'Push'
        if ($pushed) {
            if ($pushResult.Output.Count -gt 0) {
                $pushResult.Output | ForEach-Object { Write-Host $_ }
            }
            else {
                Write-SuccessLine 'Push completed.'
            }
        }
        else {
            Write-InfoLine $pushReason
        }
    }
}
