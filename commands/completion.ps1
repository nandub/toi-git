function Invoke-ToiCommand {
    param([string[]]$Arguments)

    $json = $Arguments -contains '-Json'
    $filteredArguments = @($Arguments | Where-Object { $_ -ne '-Json' })
    $action = if ($filteredArguments.Count -gt 0) { $filteredArguments[0].ToLowerInvariant() } else { 'status' }

    switch ($action) {
        'register' {
            Register-ToiArgumentCompleter

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'register'
                    registered = $true
                    command_names = @('toi', 'Invoke-Toi')
                })
                return
            }

            Write-Section 'Completion'
            Write-SuccessLine 'Registered TOI argument completion for the current PowerShell session.'
            Write-InfoLine 'Commands: toi, Invoke-Toi'
        }
        'script' {
            $script = Get-ToiCompletionRegistrationScript

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'script'
                    script = $script
                })
                return
            }

            Write-Section 'Completion'
            Write-InfoLine 'Add this to your PowerShell profile if you want manual registration:'
            Write-Host ''
            Write-Host $script
        }
        'status' {
            $registered = Test-ToiArgumentCompleterRegistered

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'status'
                    available = $registered
                    command_names = @('toi', 'Invoke-Toi')
                })
                return
            }

            Write-Section 'Completion'
            Write-KeyValue 'Available' $registered
            Write-KeyValue 'Commands' 'toi, Invoke-Toi'
            if ($registered) {
                Write-InfoLine 'Run `toi completion register` to enable completions in this session.'
            }
            else {
                Write-WarningLine 'Register-ArgumentCompleter is not available in this shell.'
            }
        }
        default {
            throw 'Usage: .\toi.ps1 completion <register|status|script> [-Json]'
        }
    }
}
