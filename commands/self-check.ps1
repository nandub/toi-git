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

    function Invoke-CommandCheck {
        param(
            [string]$Name,
            [string[]]$CommandArgs,
            [int]$TimeoutSeconds
        )

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'powershell'
        $escapedArgs = $CommandArgs | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_ -replace '"', '\"') + '"'
            }
            else {
                $_
            }
        }

        $commandText = "& .\toi.ps1 $($escapedArgs -join ' ')"
        $quotedCommandText = '"' + ($commandText -replace '"', '\"') + '"'
        $startInfo.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $quotedCommandText"
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true
        $startInfo.WorkingDirectory = $root

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $completed = $process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $completed) {
            try {
                $process.Kill()
            }
            catch {
            }

            try {
                $process.WaitForExit()
            }
            catch {
            }

            return [PSCustomObject]@{
                Success = $false
                Detail = "Timed out after ${TimeoutSeconds}s."
                Stdout = ''
                Stderr = ''
            }
        }

        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
        $process.WaitForExit()

        if ($process.ExitCode -eq 0) {
            $firstLine = (($stdout -split "(`r`n|`n|`r)") | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
            if (-not $firstLine) {
                $firstLine = 'Command completed successfully.'
            }

            return [PSCustomObject]@{
                Success = $true
                Detail = $firstLine
                Stdout = $stdout
                Stderr = $stderr
            }
        }

        $detail = (($stderr -split "(`r`n|`n|`r)") | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
        if (-not $detail) {
            $detail = 'Command failed.'
        }

        return [PSCustomObject]@{
            Success = $false
            Detail = $detail
            Stdout = $stdout
            Stderr = $stderr
        }
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

    try {
        $contractSchema = Get-ToiSchemaModel
        $null = $contractSchema.commands.status
        Add-CheckResult -Name 'Contract schema' -Success $true -Detail "Contract version: $($contractSchema.contract_version)"
    }
    catch {
        $contractSchema = $null
        Add-CheckResult -Name 'Contract schema' -Success $false -Detail $_.Exception.Message
    }

    try {
        $contractVersion = Get-ToiContractVersion
        if (-not (Test-ToiValidContractVersion -Version $contractVersion)) {
            throw "Invalid contract version '$contractVersion'. Expected semantic versioning like 1.2.3."
        }

        Add-CheckResult -Name 'Contract version format' -Success $true -Detail $contractVersion
    }
    catch {
        Add-CheckResult -Name 'Contract version format' -Success $false -Detail $_.Exception.Message
    }

    try {
        $snapshotPath = Get-ToiContractSnapshotPath
        if (-not (Test-Path -LiteralPath $snapshotPath)) {
            throw 'contracts/toi-schema.json is missing.'
        }

        $expectedSnapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
        $currentSnapshot = Get-ToiSchemaSnapshotModel
        $expectedCanonical = Convert-ToiValueToCanonicalJson -Value $expectedSnapshot
        $currentCanonical = Convert-ToiValueToCanonicalJson -Value $currentSnapshot

        if ($expectedCanonical -ne $currentCanonical) {
            throw 'Committed contract snapshot is out of date. Regenerate contracts/toi-schema.json.'
        }

        Add-CheckResult -Name 'Contract snapshot' -Success $true -Detail 'Committed schema snapshot matches current contract output.'
    }
    catch {
        Add-CheckResult -Name 'Contract snapshot' -Success $false -Detail $_.Exception.Message
    }

    $commandChecks = @(
        @{ Name = 'Help';      Args = @();            TimeoutSeconds = 10 },
        @{ Name = 'Status';    Args = @('status');    TimeoutSeconds = 15 },
        @{ Name = 'Dashboard'; Args = @('dashboard'); TimeoutSeconds = 20 },
        @{ Name = 'Install';   Args = @('install', 'profile', '-DryRun'); TimeoutSeconds = 15 },
        @{ Name = 'Install Status'; Args = @('install', 'status'); TimeoutSeconds = 15 },
        @{ Name = 'Install Module'; Args = @('install', 'module', '-DryRun'); TimeoutSeconds = 15 },
        @{ Name = 'PR Ready'; Args = @('pr', 'ready', '-DryRun'); TimeoutSeconds = 15 },
        @{ Name = 'PR Merge'; Args = @('pr', 'merge', '-DryRun'); TimeoutSeconds = 15 }
    )

    foreach ($commandCheck in $commandChecks) {
        $result = Invoke-CommandCheck -Name $commandCheck.Name -CommandArgs $commandCheck.Args -TimeoutSeconds $commandCheck.TimeoutSeconds
        Add-CheckResult -Name $commandCheck.Name -Success $result.Success -Detail $result.Detail
    }

    $jsonChecks = @(
        @{ Name = 'Status JSON'; Args = @('status', '-Json'); TimeoutSeconds = 15; Required = @('branch', 'published'); SchemaKey = 'status' },
        @{ Name = 'Dashboard JSON'; Args = @('dashboard', '-Json'); TimeoutSeconds = 20; Required = @('branch', 'working_tree', 'next_actions'); SchemaKey = 'dashboard' },
        @{ Name = 'Report JSON'; Args = @('report', '-Json'); TimeoutSeconds = 20; Required = @('generated_at', 'snapshot', 'ship'); SchemaKey = 'report' },
        @{ Name = 'Schema JSON'; Args = @('schema', '-Json'); TimeoutSeconds = 20; Required = @('contract_version', 'commands') }
    )

    foreach ($jsonCheck in $jsonChecks) {
        $result = Invoke-CommandCheck -Name $jsonCheck.Name -CommandArgs $jsonCheck.Args -TimeoutSeconds $jsonCheck.TimeoutSeconds

        if (-not $result.Success) {
            Add-CheckResult -Name $jsonCheck.Name -Success $false -Detail $result.Detail
            continue
        }

        try {
            $parsed = $result.Stdout | ConvertFrom-Json
            foreach ($field in $jsonCheck.Required) {
                if (-not ($parsed.PSObject.Properties.Name -contains $field)) {
                    throw "Missing field '$field'."
                }
            }

            if ($jsonCheck.SchemaKey -and $contractSchema) {
                $schemaEntry = $contractSchema.commands.PSObject.Properties[$jsonCheck.SchemaKey]
                if (-not $schemaEntry) {
                    throw "Missing schema entry '$($jsonCheck.SchemaKey)'."
                }

                $validationErrors = @(Get-ToiSchemaValidationErrors -Value $parsed -Schema $schemaEntry.Value)
                if ($validationErrors.Count -gt 0) {
                    throw ($validationErrors | Select-Object -First 1)
                }
            }

            Add-CheckResult -Name $jsonCheck.Name -Success $true -Detail 'JSON parsed and matched the declared contract.'
        }
        catch {
            Add-CheckResult -Name $jsonCheck.Name -Success $false -Detail $_.Exception.Message
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
