function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $filteredArguments = @($Arguments | Where-Object { $_ -ne '-Json' })

    if ($filteredArguments.Count -eq 0) {
        throw 'Usage: toi bisect <start|status|good|bad|skip|run|report|reset> [args]'
    }

    $action = $filteredArguments[0].ToLowerInvariant()

    switch ($action) {
        'start' {
            if ($filteredArguments.Count -lt 3) {
                throw 'Usage: toi bisect start <good> <bad>'
            }

            $goodRef = $filteredArguments[1]
            $badRef = $filteredArguments[2]
            $started = Start-ToiBisectSession -GoodRef $goodRef -BadRef $badRef

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'start'
                    session = $started.metadata
                    state = (Convert-ToiBisectStateToJsonModel -State $started.state)
                    output = @($started.output)
                })
                return
            }

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

            if ($json) {
                Write-Json (Convert-ToiBisectStateToJsonModel -State $state)
                return
            }

            Write-Section 'Bisect'
            Write-KeyValue 'Active' $state.active
            Write-KeyValue 'Completed' $state.completed
            Write-KeyValue 'Branch' $state.branch

            if (-not $state.active -and -not $state.completed) {
                Write-InfoLine 'No active bisect session.'
                return
            }

            if ($state.metadata) {
                Write-KeyValue 'Started' $state.metadata.started_at
                Write-KeyValue 'Started Branch' $state.metadata.started_branch
                Write-KeyValue 'Good Ref' $state.metadata.good_ref
                Write-KeyValue 'Bad Ref' $state.metadata.bad_ref
                Write-KeyValue 'Good SHA' $state.metadata.good_sha
                Write-KeyValue 'Bad SHA' $state.metadata.bad_sha
                if ($state.metadata.test_command) {
                    Write-KeyValue 'Test Command' $state.metadata.test_command
                }
            }

            if ($state.current_commit) {
                Write-KeyValue 'Current Commit' "$($state.current_commit.short_sha) $($state.current_commit.subject)"
            }

            if ($state.first_bad_commit) {
                Write-KeyValue 'First Bad Commit' "$($state.first_bad_commit.sha) $($state.first_bad_commit.subject)"
                Write-InfoLine 'Reset the session with `toi bisect reset` when you are done.'
            }

            Write-KeyValue 'Recorded Steps' $state.steps.Count
            if ($state.steps.Count -gt 0) {
                Write-Section 'Log'
                $state.steps | ForEach-Object { Write-BulletLine $_ }
            }
        }
        'good' {
            $marked = Invoke-ToiBisectMark -Mark 'good'
            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'good'
                    state = (Convert-ToiBisectStateToJsonModel -State $marked.state)
                    output = @($marked.output)
                })
                return
            }
            Write-Section 'Bisect'
            Write-SuccessLine 'Marked current commit as good.'
            if ($marked.state.current_commit) {
                Write-InfoLine "Current commit: $($marked.state.current_commit.short_sha) $($marked.state.current_commit.subject)"
            }
            $marked.output | ForEach-Object { Write-Host $_ }
        }
        'bad' {
            $marked = Invoke-ToiBisectMark -Mark 'bad'
            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'bad'
                    state = (Convert-ToiBisectStateToJsonModel -State $marked.state)
                    output = @($marked.output)
                })
                return
            }
            Write-Section 'Bisect'
            Write-WarningLine 'Marked current commit as bad.'
            if ($marked.state.current_commit) {
                Write-InfoLine "Current commit: $($marked.state.current_commit.short_sha) $($marked.state.current_commit.subject)"
            }
            $marked.output | ForEach-Object { Write-Host $_ }
        }
        'skip' {
            $marked = Invoke-ToiBisectMark -Mark 'skip'
            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'skip'
                    state = (Convert-ToiBisectStateToJsonModel -State $marked.state)
                    output = @($marked.output)
                })
                return
            }
            Write-Section 'Bisect'
            Write-WarningLine 'Skipped current commit.'
            if ($marked.state.current_commit) {
                Write-InfoLine "Current commit: $($marked.state.current_commit.short_sha) $($marked.state.current_commit.subject)"
            }
            $marked.output | ForEach-Object { Write-Host $_ }
        }
        'run' {
            if ($filteredArguments.Count -lt 2) {
                throw 'Usage: toi bisect run <command>'
            }

            $commandText = ($filteredArguments | Select-Object -Skip 1) -join ' '
            $runResult = Invoke-ToiBisectRun -CommandText $commandText

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'run'
                    command = $commandText
                    state = (Convert-ToiBisectStateToJsonModel -State $runResult.state)
                    output = @($runResult.output)
                })
                return
            }

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

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    active = $state.active
                    completed = $state.completed
                    branch = $state.branch
                    session = if ($state.metadata) {
                        [PSCustomObject]@{
                            started_at = $state.metadata.started_at
                            started_branch = $state.metadata.started_branch
                            good_ref = $state.metadata.good_ref
                            bad_ref = $state.metadata.bad_ref
                            good_sha = $state.metadata.good_sha
                            bad_sha = $state.metadata.bad_sha
                            test_command = $state.metadata.test_command
                        }
                    } else {
                        $null
                    }
                    candidate = $state.current_commit
                    first_bad_commit = $state.first_bad_commit
                    recorded_steps = $state.steps.Count
                    recent_log = @($state.steps | Select-Object -Last 5)
                })
                return
            }

            Write-Section 'Bisect Report'
            if (-not $state.active -and -not $state.completed) {
                Write-InfoLine 'No active bisect session.'
                return
            }

            if ($state.current_commit) {
                Write-KeyValue 'Candidate' "$($state.current_commit.short_sha) $($state.current_commit.subject)"
                Write-KeyValue 'SHA' $state.current_commit.sha
            }
            if ($state.first_bad_commit) {
                Write-KeyValue 'First Bad Commit' "$($state.first_bad_commit.sha) $($state.first_bad_commit.subject)"
            }
            if ($state.metadata) {
                Write-KeyValue 'Good Ref' $state.metadata.good_ref
                Write-KeyValue 'Bad Ref' $state.metadata.bad_ref
                Write-KeyValue 'Good SHA' $state.metadata.good_sha
                Write-KeyValue 'Bad SHA' $state.metadata.bad_sha
                if ($state.metadata.test_command) {
                    Write-KeyValue 'Test Command' $state.metadata.test_command
                }
            }
            Write-KeyValue 'Recorded Steps' $state.steps.Count
            if ($state.first_bad_commit) {
                Write-InfoLine 'Use `toi bisect reset` to return to your normal branch state.'
            }
            if ($state.steps.Count -gt 0) {
                Write-Section 'Recent Log'
                @($state.steps | Select-Object -Last 5) | ForEach-Object { Write-BulletLine $_ }
            }
        }
        'reset' {
            $resetResult = Reset-ToiBisectSession
            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'reset'
                    reset = $resetResult.reset
                    restored_branch = $resetResult.restored_branch
                    output = @($resetResult.output)
                })
                return
            }
            Write-Section 'Bisect'
            if (-not $resetResult.reset) {
                Write-InfoLine 'No active bisect session.'
                return
            }

            Write-SuccessLine 'Reset the bisect session.'
            if ($resetResult.restored_branch) {
                Write-InfoLine "Original branch: $($resetResult.restored_branch)"
            }
            $resetResult.output | ForEach-Object { Write-Host $_ }
        }
        default {
            throw 'Usage: toi bisect <start|status|good|bad|skip|run|report|reset> [args]'
        }
    }
}
