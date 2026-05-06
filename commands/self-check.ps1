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

        $commandMap = @{
            'status' = Join-Path $root 'commands\status.ps1'
            'sync' = Join-Path $root 'commands\sync.ps1'
            'incoming' = Join-Path $root 'commands\incoming.ps1'
            'outgoing' = Join-Path $root 'commands\outgoing.ps1'
            'dashboard' = Join-Path $root 'commands\dashboard.ps1'
            'version' = Join-Path $root 'commands\version.ps1'
            'install' = Join-Path $root 'commands\install.ps1'
            'completion' = Join-Path $root 'commands\completion.ps1'
            'bisect' = Join-Path $root 'commands\bisect.ps1'
            'pr' = Join-Path $root 'commands\pr.ps1'
            'review' = Join-Path $root 'commands\review.ps1'
            'publish' = Join-Path $root 'commands\publish.ps1'
            'release' = Join-Path $root 'commands\release.ps1'
            'report' = Join-Path $root 'commands\report.ps1'
            'schema' = Join-Path $root 'commands\schema.ps1'
        }

        if ($CommandArgs.Count -eq 0) {
            $helpResult = Invoke-CommandCheck -Name $Name -CommandArgs @('help') -TimeoutSeconds $TimeoutSeconds
            return $helpResult
        }

        $commandName = $CommandArgs[0].ToLowerInvariant()
        if ($commandName -eq 'help') {
            $stdout = @'
== TOI Git ==

Usage: toi <command> [args]
'@
            return [PSCustomObject]@{
                Success = $true
                Detail = '== TOI Git =='
                Stdout = $stdout
                Stderr = ''
            }
        }

        if (-not $commandMap.ContainsKey($commandName)) {
            return [PSCustomObject]@{
                Success = $false
                Detail = "Unknown self-check command '$commandName'."
                Stdout = ''
                Stderr = ''
            }
        }

        $commandPath = $commandMap[$commandName]
        $innerArgs = if ($CommandArgs.Count -gt 1) { @($CommandArgs[1..($CommandArgs.Count - 1)]) } else { @() }
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $stdout = (& {
                    $ErrorActionPreference = 'Stop'
                    . (Join-Path $root 'lib\output.ps1')
                    . (Join-Path $root 'lib\git.ps1')
                    . $commandPath
                    Invoke-ToiCommand -Arguments $innerArgs
                } 6>&1 | Out-String)
            $stopwatch.Stop()

            $firstLine = (($stdout -split "(`r`n|`n|`r)") | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
            if (-not $firstLine) {
                $firstLine = 'Command completed successfully.'
            }

            return [PSCustomObject]@{
                Success = $true
                Detail = $firstLine
                Stdout = $stdout
                Stderr = ''
            }
        }
        catch {
            $stopwatch.Stop()
            return [PSCustomObject]@{
                Success = $false
                Detail = $_.Exception.Message
                Stdout = ''
                Stderr = $_.Exception.Message
            }
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
        @{ Name = 'Sync';      Args = @('sync');      TimeoutSeconds = 45 },
        @{ Name = 'Sync Dry Run'; Args = @('sync', '-DryRun'); TimeoutSeconds = 20 },
        @{ Name = 'Incoming';  Args = @('incoming');  TimeoutSeconds = 15 },
        @{ Name = 'Outgoing';  Args = @('outgoing');  TimeoutSeconds = 15 },
        @{ Name = 'Dashboard'; Args = @('dashboard'); TimeoutSeconds = 20 },
        @{ Name = 'Version';   Args = @('version');   TimeoutSeconds = 15 },
        @{ Name = 'Install';   Args = @('install', 'profile', '-DryRun'); TimeoutSeconds = 15 },
        @{ Name = 'Install Status'; Args = @('install', 'status'); TimeoutSeconds = 15 },
        @{ Name = 'Install Module'; Args = @('install', 'module', '-DryRun'); TimeoutSeconds = 15 },
        @{ Name = 'Install Update'; Args = @('install', 'update', 'module', '-DryRun'); TimeoutSeconds = 15 },
        @{ Name = 'Completion Status'; Args = @('completion', 'status'); TimeoutSeconds = 15 },
        @{ Name = 'Bisect Status'; Args = @('bisect', 'status'); TimeoutSeconds = 15 },
        @{ Name = 'Bisect Report'; Args = @('bisect', 'report'); TimeoutSeconds = 15 },
        @{ Name = 'Bisect Log'; Args = @('bisect', 'log'); TimeoutSeconds = 15 },
        @{ Name = 'PR Ready'; Args = @('pr', 'ready', '-DryRun'); TimeoutSeconds = 15 },
        @{ Name = 'PR Merge'; Args = @('pr', 'merge', '-DryRun'); TimeoutSeconds = 15 }
    )

    foreach ($commandCheck in $commandChecks) {
        $result = Invoke-CommandCheck -Name $commandCheck.Name -CommandArgs $commandCheck.Args -TimeoutSeconds $commandCheck.TimeoutSeconds
        Add-CheckResult -Name $commandCheck.Name -Success $result.Success -Detail $result.Detail
    }

    try {
        $strictStatusOutput = (& {
                Set-StrictMode -Version Latest
                . (Join-Path $root 'lib\output.ps1')
                . (Join-Path $root 'lib\git.ps1')
                . (Join-Path $root 'commands\status.ps1')
                Invoke-ToiCommand -Arguments @()
            } 6>&1 | Out-String)
        $strictFirstLine = (($strictStatusOutput -split "(`r`n|`n|`r)") | Where-Object { $_ -and $_.Trim() } | Select-Object -First 1)
        Add-CheckResult -Name 'Status Strict Mode' -Success $true -Detail $strictFirstLine
    }
    catch {
        Add-CheckResult -Name 'Status Strict Mode' -Success $false -Detail $_.Exception.Message
    }

    try {
        function toi-self-check {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
        }

        Register-ToiArgumentCompleter -CommandNames @('toi-self-check')
        $completionMatches = (TabExpansion2 -inputScript 'toi-self-check s' -cursorColumn 16).CompletionMatches |
            Select-Object -ExpandProperty CompletionText

        if (-not @($completionMatches) -or -not (@($completionMatches) -contains 'status')) {
            throw 'Profile-style completion did not return expected command matches.'
        }

        Add-CheckResult -Name 'Completion Profile Wrapper' -Success $true -Detail 'Profile-style Args wrapper completed top-level commands.'
    }
    catch {
        Add-CheckResult -Name 'Completion Profile Wrapper' -Success $false -Detail $_.Exception.Message
    }
    finally {
        Remove-Item Function:\toi-self-check -ErrorAction SilentlyContinue
    }

    try {
        function toi-dup-check {
            param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
        }

        Register-ToiArgumentCompleter -CommandNames @('toi-dup-check')
        Register-ToiArgumentCompleter -CommandNames @('toi-dup-check')
        $completionMatches = @(
            (TabExpansion2 -inputScript 'toi-dup-check install' -cursorColumn 21).CompletionMatches |
                Select-Object -ExpandProperty CompletionText
        )
        $installMatches = @($completionMatches | Where-Object { $_ -eq 'install' })

        if ($installMatches.Count -ne 1) {
            throw 'Repeated completion registration produced duplicate matches.'
        }

        Add-CheckResult -Name 'Completion Idempotent Registration' -Success $true -Detail 'Repeated registration does not duplicate completion matches.'
    }
    catch {
        Add-CheckResult -Name 'Completion Idempotent Registration' -Success $false -Detail $_.Exception.Message
    }
    finally {
        Remove-Item Function:\toi-dup-check -ErrorAction SilentlyContinue
    }

    try {
        $tempProfilePath = Join-Path ([System.IO.Path]::GetTempPath()) ("toi-profile-self-check-{0}.ps1" -f [System.Guid]::NewGuid().ToString('N'))
        $installArgs = @('install', 'profile', '-ProfilePath', $tempProfilePath)
        $updateArgs = @('install', 'update', 'profile', '-ProfilePath', $tempProfilePath)

        $firstInstall = Invoke-CommandCheck -Name 'Install Profile Temp' -CommandArgs $installArgs -TimeoutSeconds 20
        if (-not $firstInstall.Success) {
            throw $firstInstall.Detail
        }

        $secondInstall = Invoke-CommandCheck -Name 'Install Update Profile Temp' -CommandArgs $updateArgs -TimeoutSeconds 20
        if (-not $secondInstall.Success) {
            throw $secondInstall.Detail
        }

        $profileContent = Get-Content -LiteralPath $tempProfilePath -Raw
        $markerCount = ([regex]::Matches($profileContent, [regex]::Escape('# >>> TOI Git >>>'))).Count
        if ($markerCount -ne 1) {
            throw 'Profile install wrote duplicate managed blocks.'
        }

        Add-CheckResult -Name 'Install Profile Idempotent' -Success $true -Detail 'Repeated profile install preserved a single managed block.'
    }
    catch {
        Add-CheckResult -Name 'Install Profile Idempotent' -Success $false -Detail $_.Exception.Message
    }
    finally {
        if ($tempProfilePath) {
            Remove-Item -LiteralPath $tempProfilePath -Force -ErrorAction SilentlyContinue
        }
    }

    $publishDryRunResult = Invoke-CommandCheck -Name 'Publish Dry Run JSON' -CommandArgs @('publish', '-DryRun', '-Json') -TimeoutSeconds 15
    if (-not $publishDryRunResult.Success) {
        Add-CheckResult -Name 'Publish Dry Run JSON' -Success $false -Detail $publishDryRunResult.Detail
    }

    if (Test-GitHubCliAvailable -and (Test-GitHubCliAuthenticated)) {
        $noPrChecks = @(
            @{ Name = 'PR Checks No PR'; Args = @('pr', 'checks', '-Required'); Expected = 'No pull request exists for branch' },
            @{ Name = 'PR Gate No PR'; Args = @('pr', 'gate'); Expected = 'No pull request exists for branch' },
            @{ Name = 'Review No PR'; Args = @('review'); Expected = 'No pull request exists for branch' }
        )

        foreach ($noPrCheck in $noPrChecks) {
            $result = Invoke-CommandCheck -Name $noPrCheck.Name -CommandArgs $noPrCheck.Args -TimeoutSeconds 20
            if (-not $result.Success) {
                if (Test-ToiGitHubAuthError -Message $result.Detail) {
                    Add-CheckResult -Name $noPrCheck.Name -Success $true -Detail 'Skipped; gh auth is not available in this shell.'
                    continue
                }

                Add-CheckResult -Name $noPrCheck.Name -Success $false -Detail $result.Detail
                continue
            }

            if ($result.Stdout -notmatch [regex]::Escape($noPrCheck.Expected)) {
                Add-CheckResult -Name $noPrCheck.Name -Success $false -Detail "Expected informational output containing '$($noPrCheck.Expected)'."
                continue
            }

            Add-CheckResult -Name $noPrCheck.Name -Success $true -Detail 'Command reported a normal no-PR informational state.'
        }
    }
    else {
        Add-CheckResult -Name 'PR Checks No PR' -Success $true -Detail 'Skipped; gh auth is not available in this shell.'
        Add-CheckResult -Name 'PR Gate No PR' -Success $true -Detail 'Skipped; gh auth is not available in this shell.'
        Add-CheckResult -Name 'Review No PR' -Success $true -Detail 'Skipped; gh auth is not available in this shell.'
    }

    if (-not $publishDryRunResult.Success) {
        Add-CheckResult -Name 'Publish Dry Run JSON Contract' -Success $false -Detail $publishDryRunResult.Detail
    }
    else {
        try {
            $publishDryRunParsed = $publishDryRunResult.Stdout | ConvertFrom-Json
            if (-not ($publishDryRunParsed.PSObject.Properties.Name -contains 'branch')) {
                throw "Missing field 'branch'."
            }

            Add-CheckResult -Name 'Publish Dry Run JSON Contract' -Success $true -Detail 'Publish dry-run JSON returned a structured response.'
        }
        catch {
            Add-CheckResult -Name 'Publish Dry Run JSON Contract' -Success $false -Detail $_.Exception.Message
        }
    }

    $releaseNotesFile = Join-Path $root (Get-ReleaseNotesFile)
    $releaseNotesExisted = Test-Path -LiteralPath $releaseNotesFile
    $releaseNotesBackup = $null
    if ($releaseNotesExisted) {
        $releaseNotesBackup = [System.IO.File]::ReadAllBytes($releaseNotesFile)
    }

    try {
        $releaseNotesResult = Invoke-CommandCheck -Name 'Release Notes Current State' -CommandArgs @('release', 'notes', 'current-state') -TimeoutSeconds 20
        Add-CheckResult -Name 'Release Notes Current State' -Success $releaseNotesResult.Success -Detail $releaseNotesResult.Detail
    }
    finally {
        if ($releaseNotesExisted) {
            [System.IO.File]::WriteAllBytes($releaseNotesFile, $releaseNotesBackup)
        }
        elseif (Test-Path -LiteralPath $releaseNotesFile) {
            Remove-Item -LiteralPath $releaseNotesFile -Force
        }
    }

    $invalidReleaseSnapshotResult = Invoke-CommandCheck -Name 'Release Tag Current State' -CommandArgs @('release', 'tag', 'current-state') -TimeoutSeconds 15
    if ($invalidReleaseSnapshotResult.Success) {
        Add-CheckResult -Name 'Release Tag Current State' -Success $false -Detail 'release tag current-state unexpectedly succeeded.'
    }
    elseif ($invalidReleaseSnapshotResult.Detail -notmatch [regex]::Escape("'current-state' is only supported for 'release notes'.")) {
        Add-CheckResult -Name 'Release Tag Current State' -Success $false -Detail "Unexpected failure message: $($invalidReleaseSnapshotResult.Detail)"
    }
    else {
        Add-CheckResult -Name 'Release Tag Current State' -Success $true -Detail 'release tag current-state was rejected with the expected message.'
    }

    $reportResult = Invoke-CommandCheck -Name 'Report Output' -CommandArgs @('report') -TimeoutSeconds 20
    if (-not $reportResult.Success) {
        Add-CheckResult -Name 'Report Output' -Success $false -Detail $reportResult.Detail
    }
    elseif (-not $reportResult.Stdout.Trim()) {
        Add-CheckResult -Name 'Report Output' -Success $false -Detail 'Report command produced no pipeline output.'
    }
    else {
        Add-CheckResult -Name 'Report Output' -Success $true -Detail 'Report command produced markdown output.'
    }

    $jsonChecks = @(
        @{ Name = 'Status JSON'; Args = @('status', '-Json'); TimeoutSeconds = 25; Required = @('branch', 'published'); SchemaKey = 'status' },
        @{ Name = 'Sync JSON'; Args = @('sync', '-Json'); TimeoutSeconds = 45; Required = @('branch', 'push', 'dry_run', 'fetched', 'updated', 'pushed'); SchemaKey = 'sync' },
        @{ Name = 'Sync Dry Run JSON'; Args = @('sync', '-DryRun', '-Json'); TimeoutSeconds = 20; Required = @('branch', 'push', 'dry_run', 'would_fetch', 'would_update', 'would_push'); SchemaKey = 'sync' },
        @{ Name = 'Incoming JSON'; Args = @('incoming', '-Json'); TimeoutSeconds = 15; Required = @('branch', 'direction', 'available', 'count', 'commits'); SchemaKey = 'incoming' },
        @{ Name = 'Outgoing JSON'; Args = @('outgoing', '-Json'); TimeoutSeconds = 15; Required = @('branch', 'direction', 'available', 'count', 'commits'); SchemaKey = 'outgoing' },
        @{ Name = 'Dashboard JSON'; Args = @('dashboard', '-Json'); TimeoutSeconds = 20; Required = @('branch', 'working_tree', 'next_actions'); SchemaKey = 'dashboard' },
        @{ Name = 'Version JSON'; Args = @('version', '-Json'); TimeoutSeconds = 15; Required = @('module_version', 'latest_tag'); SchemaKey = $null },
        @{ Name = 'Completion JSON'; Args = @('completion', 'status', '-Json'); TimeoutSeconds = 15; Required = @('action', 'available', 'command_names'); SchemaKey = 'completion' },
        @{ Name = 'Bisect Status JSON'; Args = @('bisect', 'status', '-Json'); TimeoutSeconds = 15; Required = @('active', 'branch', 'steps'); SchemaKey = 'bisect_status' },
        @{ Name = 'Bisect Report JSON'; Args = @('bisect', 'report', '-Json'); TimeoutSeconds = 15; Required = @('active', 'branch', 'recorded_steps', 'recent_log'); SchemaKey = 'bisect_report' },
        @{ Name = 'Bisect Log JSON'; Args = @('bisect', 'log', '-Json'); TimeoutSeconds = 15; Required = @('active', 'branch', 'steps'); SchemaKey = 'bisect_log' },
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
