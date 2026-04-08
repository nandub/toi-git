function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$GitArguments,

        [switch]$AllowFailure
    )

    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()

    try {
        $quotedArguments = $GitArguments | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_ -replace '(\\*)"', '$1$1\"') + '"'
            }
            else {
                $_
            }
        }

        $argumentString = $quotedArguments -join ' '
        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = 'git'
        $startInfo.Arguments = $argumentString
        $startInfo.UseShellExecute = $false
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.CreateNoWindow = $true

        $configuredSshCommand = git config --global --get core.sshCommand 2>$null
        if (-not $configuredSshCommand) {
            $startInfo.EnvironmentVariables['GIT_SSH_COMMAND'] = 'C:/Windows/System32/OpenSSH/ssh.exe'
        }

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo
        [void]$process.Start()

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $exitCode = $process.ExitCode

        $result = @()
        if ($stdout) {
            $result += ($stdout -split "(`r`n|`n|`r)" | Where-Object { $_ -and $_.Trim() })
        }

        if ($stderr) {
            $result += ($stderr -split "(`r`n|`n|`r)" | Where-Object { $_ -and $_.Trim() })
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -ErrorAction SilentlyContinue
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $message = if ($result) { ($result -join [Environment]::NewLine) } else { 'Git command failed.' }
        throw $message
    }

    return [PSCustomObject]@{
        Output   = @($result)
        ExitCode = $exitCode
    }
}

function Test-InGitRepository {
    $result = Invoke-Git -GitArguments @('rev-parse', '--is-inside-work-tree') -AllowFailure
    return $result.ExitCode -eq 0 -and ($result.Output | Select-Object -First 1) -eq 'true'
}

function Assert-InGitRepository {
    if (-not (Test-InGitRepository)) {
        throw 'Run this command inside a Git repository.'
    }
}

function Get-CurrentBranchName {
    $result = Invoke-Git -GitArguments @('branch', '--show-current')
    return ($result.Output | Select-Object -First 1).Trim()
}

function Get-StatusLines {
    $result = Invoke-Git -GitArguments @('status', '--short', '--branch')
    return @($result.Output)
}

function Get-DefaultProtectedBranches {
    return @('main', 'master', 'develop', 'dev')
}

function Test-HasCommits {
    $result = Invoke-Git -GitArguments @('rev-parse', '--verify', 'HEAD') -AllowFailure
    return $result.ExitCode -eq 0
}

function Get-CommitCount {
    if (-not (Test-HasCommits)) {
        return 0
    }

    $result = Invoke-Git -GitArguments @('rev-list', '--count', 'HEAD')
    return [int](($result.Output | Select-Object -First 1).Trim())
}

function Get-RepositoryRoot {
    $result = Invoke-Git -GitArguments @('rev-parse', '--show-toplevel')
    return ($result.Output | Select-Object -First 1).Trim()
}

function Get-RemoteUrl {
    param(
        [string]$RemoteName = 'origin'
    )

    $result = Invoke-Git -GitArguments @('remote', 'get-url', $RemoteName) -AllowFailure

    if ($result.ExitCode -ne 0) {
        return $null
    }

    return ($result.Output | Select-Object -First 1).Trim()
}

function Convert-RemoteToBrowseUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteUrl
    )

    if ($RemoteUrl -match '^git@github\.com:(.+?)(\.git)?$') {
        return "https://github.com/$($matches[1])"
    }

    if ($RemoteUrl -match '^https://github\.com/(.+?)(\.git)?$') {
        return "https://github.com/$($matches[1])"
    }

    return $RemoteUrl -replace '\.git$', ''
}

function Get-RemoteDefaultBranchRef {
    $defaultBranch = Get-DefaultBranchName
    $remoteRef = "refs/remotes/origin/$defaultBranch"

    if (Test-RefExists -RefName $remoteRef) {
        return "origin/$defaultBranch"
    }

    return $null
}

function Get-DefaultBranchComparisonRef {
    $defaultBranch = Get-DefaultBranchName

    if (Test-RefExists -RefName "refs/heads/$defaultBranch") {
        return $defaultBranch
    }

    return Get-RemoteDefaultBranchRef
}

function Get-ToiConfig {
    $repoRoot = Get-RepositoryRoot
    $configPath = Join-Path $repoRoot 'toi.json'

    $defaultConfig = [PSCustomObject]@{
        defaultBranch    = 'main'
        branchTypes      = @('feature', 'fix', 'hotfix', 'release', 'chore')
        syncStrategy     = 'rebase'
        protectBranches  = @('main')
        commitConvention = 'optional'
        qualityGateMode  = 'warn'
        validationCommands = @()
        requirePublishedForPr = $true
        dashboardSections = @('branch', 'publish', 'stack', 'gates', 'next')
        releaseBranches  = $true
        stackedBranches  = $true
    }

    if (-not (Test-Path -LiteralPath $configPath)) {
        return $defaultConfig
    }

    $raw = Get-Content -LiteralPath $configPath -Raw
    if (-not $raw.Trim()) {
        return $defaultConfig
    }

    $parsed = $raw | ConvertFrom-Json

    return [PSCustomObject]@{
        defaultBranch    = if ($parsed.defaultBranch) { [string]$parsed.defaultBranch } else { $defaultConfig.defaultBranch }
        branchTypes      = if ($parsed.branchTypes) { @($parsed.branchTypes) } else { $defaultConfig.branchTypes }
        syncStrategy     = if ($parsed.syncStrategy) { [string]$parsed.syncStrategy } else { $defaultConfig.syncStrategy }
        protectBranches  = if ($parsed.protectBranches) { @($parsed.protectBranches) } else { $defaultConfig.protectBranches }
        commitConvention = if ($parsed.commitConvention) { [string]$parsed.commitConvention } else { $defaultConfig.commitConvention }
        qualityGateMode  = if ($parsed.qualityGateMode) { [string]$parsed.qualityGateMode } else { $defaultConfig.qualityGateMode }
        validationCommands = if ($parsed.validationCommands) { @($parsed.validationCommands) } else { $defaultConfig.validationCommands }
        requirePublishedForPr = if ($null -ne $parsed.requirePublishedForPr) { [bool]$parsed.requirePublishedForPr } else { $defaultConfig.requirePublishedForPr }
        dashboardSections = if ($parsed.dashboardSections) { @($parsed.dashboardSections) } else { $defaultConfig.dashboardSections }
        releaseBranches  = if ($null -ne $parsed.releaseBranches) { [bool]$parsed.releaseBranches } else { $defaultConfig.releaseBranches }
        stackedBranches  = if ($null -ne $parsed.stackedBranches) { [bool]$parsed.stackedBranches } else { $defaultConfig.stackedBranches }
    }
}

function Get-DefaultBranchName {
    $config = Get-ToiConfig
    return $config.defaultBranch
}

function Get-ProtectedBranches {
    $config = Get-ToiConfig
    $configured = @($config.protectBranches)
    $defaults = @(Get-DefaultProtectedBranches)
    $branches = @($configured + $defaults)
    return $branches | Sort-Object -Unique
}

function Get-AllowedBranchTypes {
    $config = Get-ToiConfig
    return @($config.branchTypes)
}

function Get-SyncStrategy {
    $config = Get-ToiConfig
    return $config.syncStrategy
}

function Test-ReleaseBranchesEnabled {
    $config = Get-ToiConfig
    return [bool]$config.releaseBranches
}

function Test-StackedBranchesEnabled {
    $config = Get-ToiConfig
    return [bool]$config.stackedBranches
}

function Get-QualityGateMode {
    $config = Get-ToiConfig
    return $config.qualityGateMode
}

function Get-ValidationCommands {
    $config = Get-ToiConfig
    return @($config.validationCommands)
}

function Test-RequirePublishedForPr {
    $config = Get-ToiConfig
    return [bool]$config.requirePublishedForPr
}

function Get-DashboardSections {
    $config = Get-ToiConfig
    return @($config.dashboardSections)
}

function ConvertTo-BranchSlug {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $slug = $Name.ToLowerInvariant()
    $slug = $slug -replace '[^a-z0-9]+', '-'
    $slug = $slug.Trim('-')

    if (-not $slug) {
        throw 'Branch name must contain letters or numbers.'
    }

    return $slug
}

function New-BranchName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $slug = ConvertTo-BranchSlug -Name $Name
    return "$Type/$slug"
}

function Get-UpstreamRef {
    $result = Invoke-Git -GitArguments @('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}') -AllowFailure
    if ($result.ExitCode -ne 0) {
        return $null
    }

    return ($result.Output | Select-Object -First 1).Trim()
}

function Get-BranchRemoteRef {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [string]$RemoteName = 'origin'
    )

    return "$RemoteName/$BranchName"
}

function Test-RemoteBranchExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [string]$RemoteName = 'origin'
    )

    $remoteRef = Get-BranchRemoteRef -BranchName $BranchName -RemoteName $RemoteName
    return (Test-RefExists -RefName "refs/remotes/$remoteRef")
}

function Test-CurrentBranchPublished {
    $branch = Get-CurrentBranchName
    $upstreamRef = Get-UpstreamRef

    if ($upstreamRef) {
        return $true
    }

    return (Test-RemoteBranchExists -BranchName $branch)
}

function Test-WorkingTreeClean {
    $status = Get-StatusLines | Select-Object -Skip 1
    return $status.Count -eq 0
}

function Get-StatusSummary {
    $statusLines = Get-StatusLines | Select-Object -Skip 1
    $summary = [PSCustomObject]@{
        ChangedFiles = $statusLines.Count
        Staged       = 0
        Unstaged     = 0
        Untracked    = 0
    }

    foreach ($line in $statusLines) {
        if ($line.Length -lt 3) {
            continue
        }

        $indexState = $line.Substring(0, 1)
        $workTreeState = $line.Substring(1, 1)

        if ($indexState -eq '?' -and $workTreeState -eq '?') {
            $summary.Untracked++
            continue
        }

        if ($indexState -ne ' ') {
            $summary.Staged++
        }

        if ($workTreeState -ne ' ') {
            $summary.Unstaged++
        }
    }

    return $summary
}

function Test-RefExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RefName
    )

    $result = Invoke-Git -GitArguments @('show-ref', '--verify', '--quiet', $RefName) -AllowFailure
    return $result.ExitCode -eq 0
}

function Test-BranchExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    return (Test-RefExists -RefName "refs/heads/$BranchName")
}

function Get-BranchBaseRef {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchType,

        [switch]$Stack
    )

    $defaultBranch = Get-DefaultBranchComparisonRef
    $currentBranch = Get-CurrentBranchName

    if ($Stack) {
        return $currentBranch
    }

    if ($BranchType -eq 'hotfix' -or $BranchType -eq 'release') {
        return $defaultBranch
    }

    return $defaultBranch
}

function Get-BranchTypePattern {
    $types = Get-AllowedBranchTypes | ForEach-Object { [regex]::Escape($_) }
    return '^(' + ($types -join '|') + ')/'
}

function Test-MatchesBranchConvention {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    $pattern = Get-BranchTypePattern
    return $BranchName -match $pattern
}

function Get-AheadBehind {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LeftRef,

        [Parameter(Mandatory = $true)]
        [string]$RightRef
    )

    $result = Invoke-Git -GitArguments @('rev-list', '--left-right', '--count', "$LeftRef...$RightRef") -AllowFailure

    if ($result.ExitCode -ne 0 -or -not $result.Output) {
        return $null
    }

    $parts = (($result.Output | Select-Object -First 1).Trim() -split '\s+')
    if ($parts.Count -lt 2) {
        return $null
    }

    return [PSCustomObject]@{
        LeftAhead  = [int]$parts[0]
        RightAhead = [int]$parts[1]
    }
}

function Get-CommitRangeSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseRef,

        [Parameter(Mandatory = $true)]
        [string]$HeadRef
    )

    $result = Invoke-Git -GitArguments @('log', '--oneline', "$BaseRef..$HeadRef") -AllowFailure
    if ($result.ExitCode -ne 0) {
        return @()
    }

    return @($result.Output | Where-Object { $_ -and $_.Trim() })
}

function Get-BranchBrowseUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl,

        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    return "$RepositoryUrl/tree/$BranchName"
}

function Get-CompareBrowseUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl,

        [Parameter(Mandatory = $true)]
        [string]$BaseBranch,

        [Parameter(Mandatory = $true)]
        [string]$HeadBranch
    )

    return "$RepositoryUrl/compare/$BaseBranch...${HeadBranch}?expand=1"
}

function Get-PullRequestBrowseUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryUrl,

        [Parameter(Mandatory = $true)]
        [string]$BaseBranch,

        [Parameter(Mandatory = $true)]
        [string]$HeadBranch
    )

    return "$RepositoryUrl/compare/$BaseBranch...${HeadBranch}?expand=1&quick_pull=1"
}

function Invoke-ToiValidationCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandText
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'powershell'
    $startInfo.Arguments = "-NoProfile -NonInteractive -Command $CommandText"
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.WorkingDirectory = Get-RepositoryRoot

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()

    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()

    $output = @()
    if ($stdout) {
        $output += ($stdout -split "(`r`n|`n|`r)" | Where-Object { $_ -and $_.Trim() })
    }

    if ($stderr) {
        $output += ($stderr -split "(`r`n|`n|`r)" | Where-Object { $_ -and $_.Trim() })
    }

    return [PSCustomObject]@{
        Command  = $CommandText
        ExitCode = $process.ExitCode
        Output   = @($output)
        Success  = ($process.ExitCode -eq 0)
    }
}

function Invoke-ToiValidationSuite {
    $commands = Get-ValidationCommands

    if (-not $commands -or $commands.Count -eq 0) {
        return [PSCustomObject]@{
            HasChecks = $false
            Results   = @()
            Failed    = @()
            Passed    = @()
        }
    }

    $results = foreach ($command in $commands) {
        Invoke-ToiValidationCommand -CommandText ([string]$command)
    }

    return [PSCustomObject]@{
        HasChecks = $true
        Results   = @($results)
        Failed    = @($results | Where-Object { -not $_.Success })
        Passed    = @($results | Where-Object { $_.Success })
    }
}

function Get-ToiStackMetadataPath {
    $gitDirResult = Invoke-Git -GitArguments @('rev-parse', '--git-dir')
    $gitDir = ($gitDirResult.Output | Select-Object -First 1).Trim()
    return (Join-Path $gitDir 'toi-stack.json')
}

function Get-ToiStackMetadata {
    $path = Get-ToiStackMetadataPath

    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            branches = [PSCustomObject]@{}
        }
    }

    $raw = Get-Content -LiteralPath $path -Raw
    if (-not $raw.Trim()) {
        return [PSCustomObject]@{
            branches = [PSCustomObject]@{}
        }
    }

    $parsed = $raw | ConvertFrom-Json
    if (-not $parsed.branches) {
        $parsed | Add-Member -NotePropertyName branches -NotePropertyValue ([PSCustomObject]@{}) -Force
    }

    return $parsed
}

function Save-ToiStackMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Metadata
    )

    $path = Get-ToiStackMetadataPath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Metadata | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $path -Value $json
}

function Set-ToiStackParent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [Parameter(Mandatory = $true)]
        [string]$ParentBranch
    )

    $metadata = Get-ToiStackMetadata
    $branchesMap = [ordered]@{}

    if ($metadata.branches) {
        foreach ($property in $metadata.branches.PSObject.Properties) {
            $branchesMap[$property.Name] = $property.Value
        }
    }

    $branchesMap[$BranchName] = [PSCustomObject]@{
        parent = $ParentBranch
    }

    $metadata.branches = [PSCustomObject]$branchesMap
    Save-ToiStackMetadata -Metadata $metadata
}

function Remove-ToiStackBranch {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    $metadata = Get-ToiStackMetadata
    $branchesMap = [ordered]@{}

    if ($metadata.branches) {
        foreach ($property in $metadata.branches.PSObject.Properties) {
            if ($property.Name -ne $BranchName) {
                $branchesMap[$property.Name] = $property.Value
            }
        }
    }

    $metadata.branches = [PSCustomObject]$branchesMap
    Save-ToiStackMetadata -Metadata $metadata
}

function Get-ToiStackParent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    $metadata = Get-ToiStackMetadata
    if (-not $metadata.branches) {
        return $null
    }

    $entry = $metadata.branches.PSObject.Properties[$BranchName]
    if (-not $entry) {
        return $null
    }

    return [string]$entry.Value.parent
}

function Get-ToiStackBranches {
    $metadata = Get-ToiStackMetadata
    $items = @()

    if (-not $metadata.branches) {
        return @()
    }

    foreach ($property in $metadata.branches.PSObject.Properties) {
        $items += [PSCustomObject]@{
            Branch = $property.Name
            Parent = [string]$property.Value.parent
        }
    }

    return @($items)
}
