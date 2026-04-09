function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if ($Arguments.Count -eq 0) {
        throw 'Usage: toi bisect <start|status|good|bad|skip|run|report|reset> [args]'
    }

    $action = $Arguments[0].ToLowerInvariant()

    switch ($action) {
        'start' {
            if ($Arguments.Count -lt 3) {
                throw 'Usage: toi bisect start <good> <bad>'
            }

            $goodRef = $Arguments[1]
            $badRef = $Arguments[2]
            $started = Start-ToiBisectSession -GoodRef $goodRef -BadRef $badRef

            Write-Section 'Bisect'
            Write-InfoLine "Started: $($started.metadata.started_at)"
            Write-InfoLine "Good ref: $goodRef"
            Write-InfoLine "Bad ref: $badRef"
            Write-InfoLine "Started branch: $($started.metadata.started_branch)"
            if ($started.state.current_commit) {
                Write-InfoLine "Current commit: $($started.state.current_commit.short_sha) $($started.state.current_commit.subject)"
            }
            $started.output | ForEach-Object { Write-Host $_ }
        }
        'status' {
            $state = Get-ToiBisectState

            Write-Section 'Bisect'
            Write-KeyValue 'Active' $state.active
            Write-KeyValue 'Branch' $state.branch

            if (-not $state.active) {
                Write-InfoLine 'No active bisect session.'
                return
            }

            if ($state.metadata) {
                Write-KeyValue 'Started' $state.metadata.started_at
                Write-KeyValue 'Started Branch' $state.metadata.started_branch
                Write-KeyValue 'Good Ref' $state.metadata.good_ref
                Write-KeyValue 'Bad Ref' $state.metadata.bad_ref
                if ($state.metadata.test_command) {
                    Write-KeyValue 'Test Command' $state.metadata.test_command
                }
            }

            if ($state.current_commit) {
                Write-KeyValue 'Current Commit' "$($state.current_commit.short_sha) $($state.current_commit.subject)"
            }

            Write-KeyValue 'Recorded Steps' $state.steps.Count
            if ($state.steps.Count -gt 0) {
                Write-Section 'Log'
                $state.steps | ForEach-Object { Write-BulletLine $_ }
            }
        }
        'good' {
            $marked = Invoke-ToiBisectMark -Mark 'good'
            Write-Section 'Bisect'
            Write-SuccessLine 'Marked current commit as good.'
            if ($marked.state.current_commit) {
                Write-InfoLine "Current commit: $($marked.state.current_commit.short_sha) $($marked.state.current_commit.subject)"
            }
            $marked.output | ForEach-Object { Write-Host $_ }
        }
        'bad' {
            $marked = Invoke-ToiBisectMark -Mark 'bad'
            Write-Section 'Bisect'
            Write-WarningLine 'Marked current commit as bad.'
            if ($marked.state.current_commit) {
                Write-InfoLine "Current commit: $($marked.state.current_commit.short_sha) $($marked.state.current_commit.subject)"
            }
            $marked.output | ForEach-Object { Write-Host $_ }
        }
        'skip' {
            $marked = Invoke-ToiBisectMark -Mark 'skip'
            Write-Section 'Bisect'
            Write-WarningLine 'Skipped current commit.'
            if ($marked.state.current_commit) {
                Write-InfoLine "Current commit: $($marked.state.current_commit.short_sha) $($marked.state.current_commit.subject)"
            }
            $marked.output | ForEach-Object { Write-Host $_ }
        }
        'run' {
            if ($Arguments.Count -lt 2) {
                throw 'Usage: toi bisect run <command>'
            }

            $commandText = ($Arguments | Select-Object -Skip 1) -join ' '
            $runResult = Invoke-ToiBisectRun -CommandText $commandText

            Write-Section 'Bisect'
            Write-InfoLine "Command: $commandText"
            if ($runResult.state.current_commit) {
                Write-InfoLine "Current commit: $($runResult.state.current_commit.short_sha) $($runResult.state.current_commit.subject)"
            }
            if ($runResult.output.Count -eq 0) {
                Write-InfoLine 'Bisect run completed.'
            }
            else {
                $runResult.output | ForEach-Object { Write-Host $_ }
            }
        }
        'report' {
            $state = Get-ToiBisectState

            Write-Section 'Bisect Report'
            if (-not $state.active) {
                Write-InfoLine 'No active bisect session.'
                return
            }

            if ($state.current_commit) {
                Write-KeyValue 'Candidate' "$($state.current_commit.short_sha) $($state.current_commit.subject)"
                Write-KeyValue 'SHA' $state.current_commit.sha
            }
            if ($state.metadata) {
                Write-KeyValue 'Good Ref' $state.metadata.good_ref
                Write-KeyValue 'Bad Ref' $state.metadata.bad_ref
                if ($state.metadata.test_command) {
                    Write-KeyValue 'Test Command' $state.metadata.test_command
                }
            }
            Write-KeyValue 'Recorded Steps' $state.steps.Count
            if ($state.steps.Count -gt 0) {
                Write-Section 'Recent Log'
                @($state.steps | Select-Object -Last 5) | ForEach-Object { Write-BulletLine $_ }
            }
        }
        'reset' {
            $resetResult = Reset-ToiBisectSession
            Write-Section 'Bisect'
            if (-not $resetResult.reset) {
                Write-InfoLine 'No active bisect session.'
                return
            }

            Write-SuccessLine 'Reset the bisect session.'
            $resetResult.output | ForEach-Object { Write-Host $_ }
        }
        default {
            throw 'Usage: toi bisect <start|status|good|bad|skip|run|report|reset> [args]'
        }
    }
}
