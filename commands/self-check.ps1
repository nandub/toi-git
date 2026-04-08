function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $root = Get-RepositoryRoot
    $checks = New-Object System.Collections.Generic.List[psobject]

    function Add-CheckResult {
        param(
            [string]$Name,
            [bool]$Success,
            [string]$Detail
        )

        $checks.Add([PSCustomObject]@{
            Name    = $Name
            Success = $Success
            Detail  = $Detail
        })
    }

    try {
        $config = Get-ToiConfig
        $null = $config.defaultBranch
        Add-CheckResult -Name 'Config load' -Success $true -Detail 'toi.json parsed successfully.'
    }
    catch {
        Add-CheckResult -Name 'Config load' -Success $false -Detail $_.Exception.Message
    }

    try {
        $snapshot = Get-ToiWorkflowSnapshot
        $null = $snapshot.Branch
        Add-CheckResult -Name 'Workflow snapshot' -Success $true -Detail "Branch: $($snapshot.Branch)"
    }
    catch {
        Add-CheckResult -Name 'Workflow snapshot' -Success $false -Detail $_.Exception.Message
    }

    $commandChecks = @(
        @{ Name = 'Help';      Args = @();            TimeoutSeconds = 10 },
        @{ Name = 'Status';    Args = @('status');    TimeoutSeconds = 15 },
        @{ Name = 'Dashboard'; Args = @('dashboard'); TimeoutSeconds = 20 }
    )

    foreach ($commandCheck in $commandChecks) {
        $argList = @('-ExecutionPolicy', 'Bypass', '-File', '.\toi.ps1') + $commandCheck.Args
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'powershell'
        $startInfo.Arguments = ($argList -join ' ')
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $root

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $completed = $process.WaitForExit($commandCheck.TimeoutSeconds * 1000)

        if (-not $completed) {
            try {
                $process.Kill()
            }
            catch {
            }

            Add-CheckResult -Name $commandCheck.Name -Success $false -Detail "Timed out after $($commandCheck.TimeoutSeconds)s."
            continue
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        if ($process.ExitCode -eq 0) {
            $firstLine = (($stdout -split "(`r`n|`n|`r)") | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
            if (-not $firstLine) {
                $firstLine = 'Command completed successfully.'
            }

            Add-CheckResult -Name $commandCheck.Name -Success $true -Detail $firstLine
        }
        else {
            $detail = (($stderr -split "(`r`n|`n|`r)") | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
            if (-not $detail) {
                $detail = 'Command failed.'
            }

            Add-CheckResult -Name $commandCheck.Name -Success $false -Detail $detail
        }
    }

    $failed = @($checks | Where-Object { -not $_.Success })

    if ($json) {
        Write-Json ([PSCustomObject]@{
            checks = @($checks | ForEach-Object {
                [PSCustomObject]@{
                    name = $_.Name
                    success = $_.Success
                    detail = $_.Detail
                }
            })
            summary = [PSCustomObject]@{
                checks = $checks.Count
                passed = ($checks.Count - $failed.Count)
                failed = $failed.Count
            }
        })
    }
    else {
        Write-Section 'Self Check'

        foreach ($check in $checks) {
            if ($check.Success) {
                Write-StatusBadge -Label 'PASS' -Tone 'good'
            }
            else {
                Write-StatusBadge -Label 'FAIL' -Tone 'bad'
            }

            Write-Host " $($check.Name)"
            Write-InfoLine "  $($check.Detail)"
        }

        Write-Section 'Summary'
        Write-KeyValue 'Checks' $checks.Count
        Write-KeyValue 'Passed' ($checks.Count - $failed.Count)
        Write-KeyValue 'Failed' $failed.Count
    }

    if ($failed.Count -gt 0) {
        throw 'Self-check detected one or more failures.'
    }
}
