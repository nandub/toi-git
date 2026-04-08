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
        commitScopes     = @()
        branchNoteRequired = $false
        qualityGateMode  = 'warn'
        validationCommands = @()
        requirePublishedForPr = $true
        dashboardSections = @('branch', 'publish', 'stack', 'gates', 'next')
        releaseTagPrefix = 'v'
        releaseNotesFile = 'CHANGELOG.md'
        releaseVersionPattern = '^\d+\.\d+\.\d+$'
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
        commitScopes     = if ($parsed.commitScopes) { @($parsed.commitScopes) } else { $defaultConfig.commitScopes }
        branchNoteRequired = if ($null -ne $parsed.branchNoteRequired) { [bool]$parsed.branchNoteRequired } else { $defaultConfig.branchNoteRequired }
        qualityGateMode  = if ($parsed.qualityGateMode) { [string]$parsed.qualityGateMode } else { $defaultConfig.qualityGateMode }
        validationCommands = if ($parsed.validationCommands) { @($parsed.validationCommands) } else { $defaultConfig.validationCommands }
        requirePublishedForPr = if ($null -ne $parsed.requirePublishedForPr) { [bool]$parsed.requirePublishedForPr } else { $defaultConfig.requirePublishedForPr }
        dashboardSections = if ($parsed.dashboardSections) { @($parsed.dashboardSections) } else { $defaultConfig.dashboardSections }
        releaseTagPrefix = if ($parsed.releaseTagPrefix) { [string]$parsed.releaseTagPrefix } else { $defaultConfig.releaseTagPrefix }
        releaseNotesFile = if ($parsed.releaseNotesFile) { [string]$parsed.releaseNotesFile } else { $defaultConfig.releaseNotesFile }
        releaseVersionPattern = if ($parsed.releaseVersionPattern) { [string]$parsed.releaseVersionPattern } else { $defaultConfig.releaseVersionPattern }
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

function Get-CommitConvention {
    $config = Get-ToiConfig
    return $config.commitConvention
}

function Get-CommitScopes {
    $config = Get-ToiConfig
    return @($config.commitScopes)
}

function Test-BranchNoteRequired {
    $config = Get-ToiConfig
    return [bool]$config.branchNoteRequired
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

function Get-ReleaseTagPrefix {
    $config = Get-ToiConfig
    return $config.releaseTagPrefix
}

function Get-ReleaseNotesFile {
    $config = Get-ToiConfig
    return $config.releaseNotesFile
}

function Get-ReleaseVersionPattern {
    $config = Get-ToiConfig
    return $config.releaseVersionPattern
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

function Get-ToiNotesMetadataPath {
    $gitDirResult = Invoke-Git -GitArguments @('rev-parse', '--git-dir')
    $gitDir = ($gitDirResult.Output | Select-Object -First 1).Trim()
    return (Join-Path $gitDir 'toi-notes.json')
}

function Get-ToiNotesMetadata {
    $path = Get-ToiNotesMetadataPath

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

function Save-ToiNotesMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Metadata
    )

    $path = Get-ToiNotesMetadataPath
    $directory = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Metadata | ConvertTo-Json -Depth 10
    Set-Content -LiteralPath $path -Value $json
}

function Set-ToiBranchNote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName,

        [Parameter(Mandatory = $true)]
        [string]$Note
    )

    $metadata = Get-ToiNotesMetadata
    $branchesMap = [ordered]@{}

    if ($metadata.branches) {
        foreach ($property in $metadata.branches.PSObject.Properties) {
            $branchesMap[$property.Name] = $property.Value
        }
    }

    $branchesMap[$BranchName] = [PSCustomObject]@{
        note = $Note
    }

    $metadata.branches = [PSCustomObject]$branchesMap
    Save-ToiNotesMetadata -Metadata $metadata
}

function Get-ToiBranchNote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    $metadata = Get-ToiNotesMetadata
    if (-not $metadata.branches) {
        return $null
    }

    $entry = $metadata.branches.PSObject.Properties[$BranchName]
    if (-not $entry) {
        return $null
    }

    return [string]$entry.Value.note
}

function Remove-ToiBranchNote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BranchName
    )

    $metadata = Get-ToiNotesMetadata
    $branchesMap = [ordered]@{}

    if ($metadata.branches) {
        foreach ($property in $metadata.branches.PSObject.Properties) {
            if ($property.Name -ne $BranchName) {
                $branchesMap[$property.Name] = $property.Value
            }
        }
    }

    $metadata.branches = [PSCustomObject]$branchesMap
    Save-ToiNotesMetadata -Metadata $metadata
}

function Get-CurrentBranchType {
    $branch = Get-CurrentBranchName
    if ($branch -match '^([^/]+)/') {
        return $matches[1]
    }

    return $null
}

function Test-ConventionalCommitMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    return $Message -match '^[a-z]+(\([a-z0-9\-_]+\))?!?: .+'
}

function Get-CommitConventionHint {
    $scopes = Get-CommitScopes
    if ($scopes.Count -gt 0) {
        return "Expected format: type(scope): summary. Allowed scopes: $($scopes -join ', ')"
    }

    return 'Expected format: type(scope): summary or type: summary'
}

function Test-AllowedCommitScope {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $scopes = Get-CommitScopes
    if ($scopes.Count -eq 0) {
        return $true
    }

    if ($Message -notmatch '^[a-z]+\(([^)]+)\)!?: .+') {
        return $true
    }

    return $scopes -contains $matches[1]
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

function Test-ValidReleaseVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    $pattern = Get-ReleaseVersionPattern
    return $Version -match $pattern
}

function Get-ReleaseTagName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    return "$(Get-ReleaseTagPrefix)$Version"
}

function Get-LatestReleaseTag {
    $prefix = Get-ReleaseTagPrefix
    $result = Invoke-Git -GitArguments @('tag', '--list', "$prefix*")
    $tags = @($result.Output | Where-Object { $_ -and $_.Trim() } | Sort-Object)

    if ($tags.Count -eq 0) {
        return $null
    }

    return $tags[-1]
}

function Test-TagExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TagName
    )

    $result = Invoke-Git -GitArguments @('rev-parse', '--verify', "refs/tags/$TagName") -AllowFailure
    return $result.ExitCode -eq 0
}

function Get-ReleaseCommitRange {
    param(
        [string]$SinceRef
    )

    $head = 'HEAD'
    if ($SinceRef) {
        return "$SinceRef..$head"
    }

    return $head
}

function Get-ReleaseCommitLines {
    param(
        [string]$SinceRef
    )

    $range = Get-ReleaseCommitRange -SinceRef $SinceRef
    $args = if ($SinceRef) {
        @('log', '--oneline', $range)
    }
    else {
        @('log', '--oneline')
    }

    $result = Invoke-Git -GitArguments $args -AllowFailure
    if ($result.ExitCode -ne 0) {
        return @()
    }

    return @($result.Output | Where-Object { $_ -and $_.Trim() })
}

function New-ReleaseNotesContent {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version,

        [string]$SinceRef
    )

    $tagName = Get-ReleaseTagName -Version $Version
    $commits = Get-ReleaseCommitLines -SinceRef $SinceRef
    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("# Release $Version")
    $lines.Add('')
    $lines.Add('Tag: `' + $tagName + '`')
    $lines.Add('Generated: ' + (Get-Date -Format 'yyyy-MM-dd'))
    $lines.Add('')
    $lines.Add('## Summary')
    $lines.Add('')
    $lines.Add('- Fill in the high-level changes for this release.')
    $lines.Add('')
    $lines.Add('## Commits')
    $lines.Add('')

    if ($commits.Count -eq 0) {
        $lines.Add('- No commits found for this release range.')
    }
    else {
        foreach ($commit in $commits) {
            $lines.Add('- ' + $commit)
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Get-ToiWorkflowSnapshot {
    $branch = Get-CurrentBranchName
    $defaultBranch = Get-DefaultBranchName
    $upstreamRef = Get-UpstreamRef
    $published = Test-CurrentBranchPublished
    $status = Get-StatusSummary
    $note = Get-ToiBranchNote -BranchName $branch
    $parent = Get-ToiStackParent -BranchName $branch
    $validationSuite = Invoke-ToiValidationSuite
    $protectedBranches = Get-ProtectedBranches
    $commitConvention = Get-CommitConvention
    $branchType = Get-CurrentBranchType

    $upstreamTracking = $null
    if ($upstreamRef) {
        $upstreamTracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $upstreamRef
    }

    $defaultTracking = $null
    if ($branch -ne $defaultBranch) {
        $defaultCompareRef = Get-DefaultBranchComparisonRef
        if ($defaultCompareRef) {
            $defaultTracking = Get-AheadBehind -LeftRef 'HEAD' -RightRef $defaultCompareRef
        }
    }

    return [PSCustomObject]@{
        Branch            = $branch
        BranchType        = $branchType
        DefaultBranch     = $defaultBranch
        UpstreamRef       = $upstreamRef
        Published         = $published
        Status            = $status
        Note              = $note
        StackParent       = $parent
        ValidationSuite   = $validationSuite
        ProtectedBranches = $protectedBranches
        CommitConvention  = $commitConvention
        UpstreamTracking  = $upstreamTracking
        DefaultTracking   = $defaultTracking
        RequireBranchNote = (Test-BranchNoteRequired)
    }
}

function Get-ToiNextActions {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    $nextActions = New-Object System.Collections.Generic.List[string]

    if ($Snapshot.Status.Unstaged -gt 0 -or $Snapshot.Status.Untracked -gt 0) {
        $nextActions.Add('Clean up or checkpoint the working tree with `.\toi.ps1 save`.')
    }

    if ($Snapshot.Branch -ne $Snapshot.DefaultBranch -and -not $Snapshot.Published) {
        $nextActions.Add('Publish the branch with `.\toi.ps1 publish` when it is ready.')
    }

    if ($Snapshot.Branch -ne $Snapshot.DefaultBranch -and $Snapshot.Published) {
        $nextActions.Add('Open the PR path with `.\toi.ps1 open pr`.')
    }

    if ($Snapshot.Branch -eq $Snapshot.DefaultBranch -and $Snapshot.Status.ChangedFiles -eq 0) {
        $nextActions.Add('Create a typed branch with `.\toi.ps1 start feature <name>` for the next change.')
    }

    if ($Snapshot.RequireBranchNote -and $Snapshot.Branch -ne $Snapshot.DefaultBranch -and -not $Snapshot.Note) {
        $nextActions.Add('Add a branch note with `.\toi.ps1 note set <text>`.')
    }

    if ($Snapshot.UpstreamTracking -and $Snapshot.UpstreamTracking.RightAhead -gt 0) {
        $nextActions.Add('Sync the branch with `.\toi.ps1 sync` before pushing or opening a PR.')
    }

    if ($Snapshot.DefaultTracking -and $Snapshot.DefaultTracking.RightAhead -gt 0) {
        $nextActions.Add("Restack or rebase on $($Snapshot.DefaultBranch) to pick up newer commits.")
    }

    return @($nextActions | Select-Object -Unique)
}

function Convert-ToiSnapshotToJsonModel {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    return [PSCustomObject]@{
        branch = [PSCustomObject]@{
            current = $Snapshot.Branch
            type = $Snapshot.BranchType
            default = $Snapshot.DefaultBranch
            published = $Snapshot.Published
            note = $Snapshot.Note
            commit_convention = $Snapshot.CommitConvention
        }
        working_tree = [PSCustomObject]@{
            changed_files = $Snapshot.Status.ChangedFiles
            staged = $Snapshot.Status.Staged
            unstaged = $Snapshot.Status.Unstaged
            untracked = $Snapshot.Status.Untracked
        }
        publish = [PSCustomObject]@{
            upstream = $Snapshot.UpstreamRef
            ahead = if ($Snapshot.UpstreamTracking) { $Snapshot.UpstreamTracking.LeftAhead } else { $null }
            behind = if ($Snapshot.UpstreamTracking) { $Snapshot.UpstreamTracking.RightAhead } else { $null }
        }
        stack = [PSCustomObject]@{
            parent = $Snapshot.StackParent
            behind_default = if ($Snapshot.DefaultTracking) { $Snapshot.DefaultTracking.RightAhead } else { $null }
        }
        quality_gates = [PSCustomObject]@{
            mode = Get-QualityGateMode
            has_checks = $Snapshot.ValidationSuite.HasChecks
            results = @($Snapshot.ValidationSuite.Results | ForEach-Object {
                [PSCustomObject]@{
                    command = $_.Command
                    success = $_.Success
                    exit_code = $_.ExitCode
                }
            })
        }
        policy = [PSCustomObject]@{
            require_branch_note = $Snapshot.RequireBranchNote
        }
    }
}

function Get-ToiDoctorRecommendations {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    $recommendations = New-Object System.Collections.Generic.List[string]

    if ($Snapshot.ProtectedBranches -contains $Snapshot.Branch -and ($Snapshot.Status.Unstaged -gt 0 -or $Snapshot.Status.Untracked -gt 0)) {
        $recommendations.Add("Avoid doing feature work directly on '$($Snapshot.Branch)'. Create a branch with `.\toi.ps1 start feature <name>`.")
    }

    if ($Snapshot.RequireBranchNote -and $Snapshot.Branch -ne $Snapshot.DefaultBranch -and -not $Snapshot.Note) {
        $recommendations.Add('Add a branch note with `.\toi.ps1 note set <text>`.')
    }

    if ($Snapshot.UpstreamTracking) {
        if ($Snapshot.UpstreamTracking.RightAhead -gt 0) {
            $recommendations.Add('Run `.\toi.ps1 sync` before pushing or opening a PR.')
        }

        if ($Snapshot.UpstreamTracking.LeftAhead -gt 0) {
            $recommendations.Add('Branch has local commits ready to push or review.')
        }
    }
    elseif ($Snapshot.Branch -ne $Snapshot.DefaultBranch) {
        $recommendations.Add('Run `.\toi.ps1 publish` when this branch is ready for review.')
    }

    if ($Snapshot.DefaultTracking -and $Snapshot.DefaultTracking.RightAhead -gt 0) {
        $recommendations.Add('Rebase or sync against the default branch before shipping.')
    }

    if ($Snapshot.UpstreamRef -and $Snapshot.DefaultTracking -and $Snapshot.DefaultTracking.LeftAhead -gt 0) {
        $recommendations.Add('Open a PR with `.\toi.ps1 open pr` when the branch is ready.')
    }

    return @($recommendations | Select-Object -Unique)
}

function Get-ToiShipAssessment {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    $blockingIssues = New-Object System.Collections.Generic.List[string]
    $notes = New-Object System.Collections.Generic.List[string]
    $qualityGateMode = Get-QualityGateMode

    if ($Snapshot.ProtectedBranches -contains $Snapshot.Branch) {
        $blockingIssues.Add("Refusing to ship directly from protected branch '$($Snapshot.Branch)'.")
    }

    if ($Snapshot.Status.Unstaged -gt 0 -or $Snapshot.Status.Untracked -gt 0) {
        $blockingIssues.Add('Working tree is not clean enough for shipping.')
        $notes.Add('Use `.\toi.ps1 save` or commit/stage intentionally first.')
    }

    if (-not (Test-MatchesBranchConvention -BranchName $Snapshot.Branch) -and $Snapshot.ProtectedBranches -notcontains $Snapshot.Branch) {
        $notes.Add('Branch name is outside TOI conventions.')
    }

    if ($Snapshot.DefaultTracking -and $Snapshot.DefaultTracking.RightAhead -gt 0) {
        $blockingIssues.Add("Branch is behind $($Snapshot.DefaultBranch) by $($Snapshot.DefaultTracking.RightAhead) commit(s).")
    }

    if ($Snapshot.UpstreamTracking) {
        if ($Snapshot.UpstreamTracking.RightAhead -gt 0) {
            $blockingIssues.Add('Branch is behind its upstream.')
        }

        if ($Snapshot.UpstreamTracking.LeftAhead -eq 0 -and $Snapshot.UpstreamTracking.RightAhead -eq 0 -and $Snapshot.Branch -ne $Snapshot.DefaultBranch) {
            $notes.Add('No local commits to push.')
        }

        if ($Snapshot.UpstreamTracking.LeftAhead -gt 0 -and $Snapshot.Branch -ne $Snapshot.DefaultBranch) {
            $notes.Add('Branch has local commits ready to push or review.')
        }
    }
    elseif ($Snapshot.Branch -eq $Snapshot.DefaultBranch) {
        $notes.Add('Default branch has no upstream configured.')
    }
    else {
        $notes.Add('Branch is local only. Run `.\toi.ps1 publish` to push it and set upstream.')
    }

    if ($Snapshot.ValidationSuite.HasChecks) {
        foreach ($result in $Snapshot.ValidationSuite.Results) {
            if (-not $result.Success) {
                if ($qualityGateMode -eq 'block') {
                    $blockingIssues.Add("Quality gate failed: $($result.Command)")
                }
                else {
                    $notes.Add("Quality gate failed in warn mode: $($result.Command)")
                }
            }
        }
    }

    return [PSCustomObject]@{
        blocking_issues = @($blockingIssues | Select-Object -Unique)
        notes = @($notes | Select-Object -Unique)
        quality_gate_mode = $qualityGateMode
    }
}

function Get-ToiReportModel {
    $snapshot = Get-ToiWorkflowSnapshot
    $nextActions = Get-ToiNextActions -Snapshot $snapshot
    $doctorRecommendations = Get-ToiDoctorRecommendations -Snapshot $snapshot
    $shipAssessment = Get-ToiShipAssessment -Snapshot $snapshot
    $commitRange = if ($snapshot.Branch -ne $snapshot.DefaultBranch -and (Get-DefaultBranchComparisonRef)) {
        Get-CommitRangeSummary -BaseRef (Get-DefaultBranchComparisonRef) -HeadRef 'HEAD'
    }
    else {
        @()
    }

    return [PSCustomObject]@{
        generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        snapshot = Convert-ToiSnapshotToJsonModel -Snapshot $snapshot
        next_actions = @($nextActions)
        doctor = [PSCustomObject]@{
            recommendations = @($doctorRecommendations)
        }
        ship = [PSCustomObject]@{
            blocking_issues = @($shipAssessment.blocking_issues)
            notes = @($shipAssessment.notes)
            commit_range = @($commitRange)
            shippable = ($shipAssessment.blocking_issues.Count -eq 0)
        }
    }
}

function Convert-ToiReportToMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# TOI Workflow Report')
    $lines.Add('')
    $lines.Add("Generated: $($Report.generated_at)")
    $lines.Add('')
    $lines.Add('## Branch')
    $lines.Add('')
    $lines.Add("- Current: $($Report.snapshot.branch.current)")
    $lines.Add("- Default: $($Report.snapshot.branch.default)")
    $lines.Add("- Type: $(if ($Report.snapshot.branch.type) { $Report.snapshot.branch.type } else { 'n/a' })")
    $lines.Add("- Published: $($Report.snapshot.branch.published)")
    $lines.Add("- Commit convention: $($Report.snapshot.branch.commit_convention)")
    if ($Report.snapshot.branch.note) {
        $lines.Add("- Note: $($Report.snapshot.branch.note)")
    }
    $lines.Add('')
    $lines.Add('## Working Tree')
    $lines.Add('')
    $lines.Add("- Changed files: $($Report.snapshot.working_tree.changed_files)")
    $lines.Add("- Staged: $($Report.snapshot.working_tree.staged)")
    $lines.Add("- Unstaged: $($Report.snapshot.working_tree.unstaged)")
    $lines.Add("- Untracked: $($Report.snapshot.working_tree.untracked)")
    $lines.Add('')
    $lines.Add('## Publish')
    $lines.Add('')
    $lines.Add("- Upstream: $(if ($Report.snapshot.publish.upstream) { $Report.snapshot.publish.upstream } else { 'none' })")
    if ($null -ne $Report.snapshot.publish.ahead) {
        $lines.Add("- Ahead: $($Report.snapshot.publish.ahead)")
    }
    if ($null -ne $Report.snapshot.publish.behind) {
        $lines.Add("- Behind: $($Report.snapshot.publish.behind)")
    }
    $lines.Add('')
    $lines.Add('## Ship')
    $lines.Add('')
    $lines.Add("- Shippable: $($Report.ship.shippable)")
    if ($Report.ship.blocking_issues.Count -gt 0) {
        $lines.Add('- Blocking issues:')
        foreach ($item in $Report.ship.blocking_issues) {
            $lines.Add("  - $item")
        }
    }
    if ($Report.ship.notes.Count -gt 0) {
        $lines.Add('- Notes:')
        foreach ($item in $Report.ship.notes) {
            $lines.Add("  - $item")
        }
    }
    $lines.Add('')
    $lines.Add('## Next Actions')
    $lines.Add('')
    if ($Report.next_actions.Count -eq 0) {
        $lines.Add('- No obvious next action.')
    }
    else {
        foreach ($item in $Report.next_actions) {
            $lines.Add("- $item")
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Get-ToiContractVersion {
    return '1.0.0'
}

function New-ToiSchemaField {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [string]$Description,

        [object]$Items
    )

    $field = [ordered]@{
        type = $Type
    }

    if ($Description) {
        $field.description = $Description
    }

    if ($null -ne $Items) {
        $field.items = $Items
    }

    return [PSCustomObject]$field
}

function Get-ToiJsonCommandSchemas {
    $stringArray = New-ToiSchemaField -Type 'array' -Description 'Array of strings.' -Items ([PSCustomObject]@{ type = 'string' })
    $qualityGateArray = New-ToiSchemaField -Type 'array' -Description 'Array of quality gate results.' -Items ([PSCustomObject]@{
        type = 'object'
        properties = [PSCustomObject]@{
            command = 'string'
            success = 'boolean'
            exit_code = 'number'
        }
    })

    return [PSCustomObject]@{
        status = [PSCustomObject]@{
            required = @('branch', 'published', 'upstream', 'branch_line', 'staged', 'unstaged', 'untracked')
            properties = [PSCustomObject]@{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                published = New-ToiSchemaField -Type 'boolean' -Description 'Whether the current branch exists on a remote.'
                upstream = New-ToiSchemaField -Type 'string|null' -Description 'Configured upstream ref, if present.'
                branch_line = New-ToiSchemaField -Type 'string' -Description 'Raw `git status --short --branch` headline.'
                staged = $stringArray
                unstaged = $stringArray
                untracked = $stringArray
            }
        }
        dashboard = [PSCustomObject]@{
            required = @('branch', 'working_tree', 'publish', 'stack', 'quality_gates', 'policy', 'next_actions')
            properties = [PSCustomObject]@{
                branch = New-ToiSchemaField -Type 'object' -Description 'Branch-level workflow metadata.'
                working_tree = New-ToiSchemaField -Type 'object' -Description 'Working tree counts.'
                publish = New-ToiSchemaField -Type 'object' -Description 'Publish/upstream status.'
                stack = New-ToiSchemaField -Type 'object' -Description 'Stack-parent and default-branch comparison state.'
                quality_gates = New-ToiSchemaField -Type 'object' -Description 'Configured validation mode and latest results.'
                policy = New-ToiSchemaField -Type 'object' -Description 'Active workflow policy flags.'
                next_actions = $stringArray
            }
        }
        next = [PSCustomObject]@{
            required = @('branch', 'message', 'published')
            properties = [PSCustomObject]@{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                message = New-ToiSchemaField -Type 'string' -Description 'Single recommended next action.'
                published = New-ToiSchemaField -Type 'boolean' -Description 'Whether the branch is published.'
            }
        }
        doctor = [PSCustomObject]@{
            required = @('branch', 'working_tree', 'publish', 'stack', 'quality_gates', 'policy', 'recommendations')
            properties = [PSCustomObject]@{
                branch = New-ToiSchemaField -Type 'object' -Description 'Branch-level workflow metadata.'
                working_tree = New-ToiSchemaField -Type 'object' -Description 'Working tree counts.'
                publish = New-ToiSchemaField -Type 'object' -Description 'Publish/upstream status.'
                stack = New-ToiSchemaField -Type 'object' -Description 'Stack-parent and default-branch comparison state.'
                quality_gates = New-ToiSchemaField -Type 'object' -Description 'Configured validation mode and latest results.'
                policy = New-ToiSchemaField -Type 'object' -Description 'Active workflow policy flags.'
                recommendations = $stringArray
            }
        }
        ship = [PSCustomObject]@{
            required = @('branch', 'working_tree', 'publish', 'stack', 'quality_gates', 'policy', 'ship')
            properties = [PSCustomObject]@{
                branch = New-ToiSchemaField -Type 'object' -Description 'Branch-level workflow metadata.'
                working_tree = New-ToiSchemaField -Type 'object' -Description 'Working tree counts.'
                publish = New-ToiSchemaField -Type 'object' -Description 'Publish/upstream status.'
                stack = New-ToiSchemaField -Type 'object' -Description 'Stack-parent and default-branch comparison state.'
                quality_gates = New-ToiSchemaField -Type 'object' -Description 'Configured validation mode and latest results.'
                policy = New-ToiSchemaField -Type 'object' -Description 'Active workflow policy flags.'
                ship = New-ToiSchemaField -Type 'object' -Description 'Shipping assessment and commit range.'
            }
        }
        publish = [PSCustomObject]@{
            required = @('branch', 'dry_run', 'quality_gate_mode', 'upstream', 'branch_url', 'pr_url', 'push_output', 'quality_gates')
            properties = [PSCustomObject]@{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                dry_run = New-ToiSchemaField -Type 'boolean' -Description 'Whether publish ran in dry-run mode.'
                quality_gate_mode = New-ToiSchemaField -Type 'string' -Description 'Configured quality gate mode.'
                upstream = New-ToiSchemaField -Type 'string|null' -Description 'Configured upstream ref before push.'
                branch_url = New-ToiSchemaField -Type 'string' -Description 'GitHub branch URL.'
                pr_url = New-ToiSchemaField -Type 'string' -Description 'GitHub compare/PR URL.'
                push_output = $stringArray
                quality_gates = $qualityGateArray
            }
            blocked_shape = [PSCustomObject]@{
                required = @('blocked', 'reason', 'branch')
                properties = [PSCustomObject]@{
                    blocked = New-ToiSchemaField -Type 'boolean' -Description 'Whether publish was blocked before push.'
                    reason = New-ToiSchemaField -Type 'string' -Description 'Human-readable block reason.'
                    branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                }
            }
        }
        self_check = [PSCustomObject]@{
            required = @('checks', 'summary')
            properties = [PSCustomObject]@{
                checks = New-ToiSchemaField -Type 'array' -Description 'Per-check results.' -Items ([PSCustomObject]@{
                    type = 'object'
                    properties = [PSCustomObject]@{
                        name = 'string'
                        success = 'boolean'
                        detail = 'string'
                    }
                })
                summary = New-ToiSchemaField -Type 'object' -Description 'Aggregate pass/fail counts.'
            }
        }
        report = [PSCustomObject]@{
            required = @('generated_at', 'snapshot', 'next_actions', 'doctor', 'ship')
            properties = [PSCustomObject]@{
                generated_at = New-ToiSchemaField -Type 'string' -Description 'Local timestamp when the report was generated.'
                snapshot = New-ToiSchemaField -Type 'object' -Description 'Workflow snapshot model.'
                next_actions = $stringArray
                doctor = New-ToiSchemaField -Type 'object' -Description 'Doctor recommendations.'
                ship = New-ToiSchemaField -Type 'object' -Description 'Shipping assessment.'
            }
        }
    }
}

function Get-ToiSchemaModel {
    return [PSCustomObject]@{
        contract_version = Get-ToiContractVersion
        generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        commands = Get-ToiJsonCommandSchemas
    }
}

function Convert-ToiSchemaToMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Schema
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# TOI JSON Contracts')
    $lines.Add('')
    $lines.Add("Contract version: $($Schema.contract_version)")
    $lines.Add("Generated: $($Schema.generated_at)")
    $lines.Add('')

    foreach ($command in $Schema.commands.PSObject.Properties) {
        $lines.Add("## $($command.Name)")
        $lines.Add('')
        $lines.Add('Required fields:')
        foreach ($field in $command.Value.required) {
            $lines.Add("- $field")
        }
        $lines.Add('')
    }

    return ($lines -join [Environment]::NewLine)
}
