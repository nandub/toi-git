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
        dashboardSections = @('branch', 'publish', 'stack', 'pr', 'gates', 'contract', 'next')
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

function Test-GitHubCliAvailable {
    $command = Get-Command gh -ErrorAction SilentlyContinue
    return $null -ne $command
}

function Test-GitHubCliAuthenticated {
    if (-not (Test-GitHubCliAvailable)) {
        return $false
    }

    $result = Invoke-GitHubCli -Arguments @('auth', 'status') -AllowFailure
    return $result.ExitCode -eq 0
}

function Invoke-GitHubCli {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    $argumentString = ($Arguments | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_ -replace '(\\*)"', '$1$1\"') + '"'
            }
            else {
                $_
            }
        }) -join ' '

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = 'gh'
    $startInfo.Arguments = $argumentString
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

    $result = @()
    if ($stdout) {
        $result += ($stdout -split "(`r`n|`n|`r)" | Where-Object { $_ -and $_.Trim() })
    }

    if ($stderr) {
        $result += ($stderr -split "(`r`n|`n|`r)" | Where-Object { $_ -and $_.Trim() })
    }

    if (-not $AllowFailure -and $process.ExitCode -ne 0) {
        $message = if ($result) { ($result -join [Environment]::NewLine) } else { 'GitHub CLI command failed.' }
        throw $message
    }

    return [PSCustomObject]@{
        Output   = @($result)
        ExitCode = $process.ExitCode
    }
}

function Open-ToiPullRequest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FallbackUrl
    )

    if (-not (Test-GitHubCliAvailable)) {
        Start-Process $FallbackUrl | Out-Null
        return [PSCustomObject]@{
            Method = 'browser'
            Detail = $FallbackUrl
        }
    }

    $viewResult = Invoke-GitHubCli -Arguments @('pr', 'view', '--web') -AllowFailure
    if ($viewResult.ExitCode -eq 0) {
        return [PSCustomObject]@{
            Method = 'gh'
            Detail = 'Opened pull request with gh pr view --web.'
        }
    }

    $createResult = Invoke-GitHubCli -Arguments @('pr', 'create', '--fill', '--web') -AllowFailure
    if ($createResult.ExitCode -eq 0) {
        return [PSCustomObject]@{
            Method = 'gh'
            Detail = 'Opened pull request creation flow with gh pr create --fill --web.'
        }
    }

    Start-Process $FallbackUrl | Out-Null
    return [PSCustomObject]@{
        Method = 'browser'
        Detail = $FallbackUrl
    }
}

function Publish-ToiGitHubRelease {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TagName,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$NotesFile,

        [switch]$Draft,

        [switch]$DryRun
    )

    if (-not (Test-GitHubCliAvailable)) {
        throw 'gh.exe is not available on PATH.'
    }

    $arguments = @('release', 'create', $TagName, '--title', $Title, '--notes-file', $NotesFile)
    if ($Draft) {
        $arguments += '--draft'
    }

    if ($DryRun) {
        return [PSCustomObject]@{
            Arguments = @($arguments)
            DryRun = $true
            Output = @()
            ExitCode = 0
        }
    }

    $result = Invoke-GitHubCli -Arguments $arguments
    return [PSCustomObject]@{
        Arguments = @($arguments)
        DryRun = $false
        Output = @($result.Output)
        ExitCode = $result.ExitCode
    }
}

function Get-ToiPullRequestInfo {
    $fields = 'number,title,url,state,isDraft,reviewDecision,mergeStateStatus,headRefName,baseRefName,reviewRequests,latestReviews'
    $result = Invoke-GitHubCli -Arguments @('pr', 'view', '--json', $fields)
    $jsonText = ($result.Output -join [Environment]::NewLine)
    return ($jsonText | ConvertFrom-Json)
}

function Get-ToiPullRequestRequestedReviewers {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PullRequest
    )

    $names = New-Object System.Collections.Generic.List[string]
    $reviewRequests = @($PullRequest.reviewRequests)

    foreach ($request in $reviewRequests) {
        $candidate = $null

        if ($request.requestedReviewer) {
            if ($request.requestedReviewer.login) {
                $candidate = "@$($request.requestedReviewer.login)"
            }
            elseif ($request.requestedReviewer.name) {
                $candidate = [string]$request.requestedReviewer.name
            }
        }

        if (-not $candidate -and $request.requestedTeam) {
            if ($request.requestedTeam.name) {
                $candidate = $request.requestedTeam.name
            }
            elseif ($request.requestedTeam.slug) {
                $candidate = $request.requestedTeam.slug
            }
        }

        if (-not $candidate -and $request.name) {
            $candidate = [string]$request.name
        }

        if (-not $candidate -and $request.login) {
            $candidate = "@$($request.login)"
        }

        if ($candidate) {
            $names.Add($candidate)
        }
    }

    return @($names | Sort-Object -Unique)
}

function Get-ToiPullRequestLatestReviewSummary {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PullRequest
    )

    $reviews = @($PullRequest.latestReviews)
    $states = @($reviews | ForEach-Object { $_.state } | Where-Object { $_ })

    return [PSCustomObject]@{
        approved = @($states | Where-Object { $_ -eq 'APPROVED' }).Count
        changes_requested = @($states | Where-Object { $_ -eq 'CHANGES_REQUESTED' }).Count
        commented = @($states | Where-Object { $_ -eq 'COMMENTED' }).Count
    }
}

function Get-ToiPullRequestLatestReviewDetails {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$PullRequest
    )

    $items = New-Object System.Collections.Generic.List[object]

    foreach ($review in @($PullRequest.latestReviews)) {
        $reviewer = $null
        if ($review.author) {
            if ($review.author.login) {
                $reviewer = "@$($review.author.login)"
            }
            elseif ($review.author.name) {
                $reviewer = [string]$review.author.name
            }
        }

        if (-not $reviewer) {
            $reviewer = 'unknown'
        }

        $items.Add([PSCustomObject]@{
            reviewer = $reviewer
            state = [string]$review.state
        })
    }

    return @($items)
}

function Get-ToiPullRequestChecks {
    param([switch]$Required)

    $arguments = @('pr', 'checks', '--json', 'bucket,completedAt,description,event,link,name,startedAt,state,workflow')
    if ($Required) {
        $arguments += '--required'
    }

    $result = Invoke-GitHubCli -Arguments $arguments
    $jsonText = ($result.Output -join [Environment]::NewLine)
    $parsed = $jsonText | ConvertFrom-Json

    if ($parsed -is [System.Array]) {
        return @($parsed)
    }

    return @($parsed)
}

function Get-ToiPullRequestChecksSummary {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Checks
    )

    return [PSCustomObject]@{
        pass = @($Checks | Where-Object { $_.bucket -eq 'pass' }).Count
        fail = @($Checks | Where-Object { $_.bucket -eq 'fail' }).Count
        pending = @($Checks | Where-Object { $_.bucket -eq 'pending' }).Count
        cancel = @($Checks | Where-Object { $_.bucket -eq 'cancel' }).Count
        skipping = @($Checks | Where-Object { $_.bucket -eq 'skipping' }).Count
    }
}

function Set-ToiPullRequestReady {
    param(
        [switch]$Undo,
        [switch]$DryRun
    )

    $arguments = @('pr', 'ready')
    if ($Undo) {
        $arguments += '--undo'
    }

    if ($DryRun) {
        return [PSCustomObject]@{
            Command = @($arguments)
            Output = @()
        }
    }

    $result = Invoke-GitHubCli -Arguments $arguments
    return [PSCustomObject]@{
        Command = @($arguments)
        Output = @($result.Output)
    }
}

function Merge-ToiPullRequest {
    param(
        [ValidateSet('merge', 'rebase', 'squash')]
        [string]$Strategy = 'squash',

        [switch]$DeleteBranch,
        [switch]$Auto,
        [switch]$Admin,
        [switch]$DryRun
    )

    $arguments = @('pr', 'merge')

    switch ($Strategy) {
        'merge' { $arguments += '--merge' }
        'rebase' { $arguments += '--rebase' }
        'squash' { $arguments += '--squash' }
    }

    if ($DeleteBranch) {
        $arguments += '--delete-branch'
    }

    if ($Auto) {
        $arguments += '--auto'
    }

    if ($Admin) {
        $arguments += '--admin'
    }

    if ($DryRun) {
        return [PSCustomObject]@{
            Command = @($arguments)
            Output = @()
        }
    }

    $result = Invoke-GitHubCli -Arguments $arguments
    return [PSCustomObject]@{
        Command = @($arguments)
        Output = @($result.Output)
    }
}

function Get-ToiPullRequestGateStatus {
    $pr = Get-ToiPullRequestInfo
    $checks = @(Get-ToiPullRequestChecks -Required)
    $summary = Get-ToiPullRequestChecksSummary -Checks $checks
    $requestedReviewers = @(Get-ToiPullRequestRequestedReviewers -PullRequest $pr)
    $reviewSummary = Get-ToiPullRequestLatestReviewSummary -PullRequest $pr
    $blockers = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]

    if ($pr.state -ne 'OPEN') {
        $blockers.Add("PR state is '$($pr.state)'.")
    }

    if ($pr.isDraft) {
        $blockers.Add('PR is still a draft.')
    }

    if ($pr.reviewDecision -eq 'CHANGES_REQUESTED') {
        $blockers.Add('Review decision is CHANGES_REQUESTED.')
    }
    elseif ($pr.reviewDecision -eq 'REVIEW_REQUIRED') {
        $blockers.Add('GitHub still requires review before merge.')
    }
    elseif (-not $pr.reviewDecision) {
        $warnings.Add('No review decision is currently available.')
    }

    if ($requestedReviewers.Count -gt 0) {
        $blockers.Add('Pending review requests: ' + ($requestedReviewers -join ', '))
    }

    if ($summary.fail -gt 0) {
        $blockers.Add("There are $($summary.fail) failing required check(s).")
    }

    if ($summary.pending -gt 0) {
        $blockers.Add("There are $($summary.pending) pending required check(s).")
    }

    switch ($pr.mergeStateStatus) {
        'BLOCKED' { $blockers.Add('GitHub reports the PR as BLOCKED.') }
        'DIRTY' { $blockers.Add('GitHub reports merge conflicts for this PR.') }
        'BEHIND' { $blockers.Add('PR branch is behind the base branch.') }
        'UNKNOWN' { $warnings.Add('GitHub merge state is UNKNOWN.') }
        'UNSTABLE' { $warnings.Add('GitHub merge state is UNSTABLE.') }
        default { }
    }

    if ($checks.Count -eq 0) {
        $warnings.Add('No required checks were returned by GitHub.')
    }

    $recommendedAction = 'review'
    $recommendedCommand = '.\toi.ps1 pr status'

    if ($blockers.Count -eq 0) {
        $recommendedAction = 'merge'
        $recommendedCommand = '.\toi.ps1 pr merge -Squash -DeleteBranch'
    }
    elseif ($pr.isDraft) {
        $recommendedAction = 'ready'
        $recommendedCommand = '.\toi.ps1 pr ready'
    }
    elseif ($requestedReviewers.Count -gt 0 -or $pr.reviewDecision -eq 'REVIEW_REQUIRED') {
        $recommendedAction = 'wait-for-review'
        $recommendedCommand = '.\toi.ps1 pr status'
    }
    elseif ($summary.pending -gt 0) {
        $recommendedAction = 'wait-for-checks'
        $recommendedCommand = '.\toi.ps1 pr checks -Required'
    }
    elseif ($summary.fail -gt 0) {
        $recommendedAction = 'fix-checks'
        $recommendedCommand = '.\toi.ps1 pr checks -Required'
    }
    elseif ($pr.mergeStateStatus -eq 'BEHIND') {
        $recommendedAction = 'sync-branch'
        $recommendedCommand = '.\toi.ps1 sync'
    }
    elseif ($pr.reviewDecision -eq 'CHANGES_REQUESTED') {
        $recommendedAction = 'address-review'
        $recommendedCommand = '.\toi.ps1 pr status'
    }

    return [PSCustomObject]@{
        ready = ($blockers.Count -eq 0)
        branch = $pr.headRefName
        title = $pr.title
        url = $pr.url
        draft = [bool]$pr.isDraft
        state = $pr.state
        review_decision = $pr.reviewDecision
        merge_state = $pr.mergeStateStatus
        requested_reviewers = @($requestedReviewers)
        reviews = [PSCustomObject]@{
            approved = $reviewSummary.approved
            changes_requested = $reviewSummary.changes_requested
            commented = $reviewSummary.commented
        }
        checks = [PSCustomObject]@{
            pass = $summary.pass
            fail = $summary.fail
            pending = $summary.pending
            cancel = $summary.cancel
            skipping = $summary.skipping
        }
        recommended_action = $recommendedAction
        recommended_command = $recommendedCommand
        blockers = @($blockers)
        warnings = @($warnings)
    }
}

function Get-ToiPullRequestReviewSummary {
    $pr = Get-ToiPullRequestInfo
    $gate = Get-ToiPullRequestGateStatus
    $reviewSummary = Get-ToiPullRequestLatestReviewSummary -PullRequest $pr
    $latestReviews = Get-ToiPullRequestLatestReviewDetails -PullRequest $pr

    return [PSCustomObject]@{
        title = $pr.title
        branch = $pr.headRefName
        url = $pr.url
        review_decision = $pr.reviewDecision
        requested_reviewers = @($gate.requested_reviewers)
        reviews = [PSCustomObject]@{
            approved = $reviewSummary.approved
            changes_requested = $reviewSummary.changes_requested
            commented = $reviewSummary.commented
        }
        latest_reviews = @($latestReviews)
        ready = $gate.ready
        recommended_action = $gate.recommended_action
        recommended_command = $gate.recommended_command
        blockers = @($gate.blockers)
        warnings = @($gate.warnings)
    }
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
    $contractStatus = Get-ToiContractStatus
    $pullRequestGate = $null

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

    if ($branch -ne $defaultBranch -and $published -and (Test-GitHubCliAuthenticated)) {
        try {
            $pullRequestGate = Get-ToiPullRequestGateStatus
        }
        catch {
            $pullRequestGate = $null
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
        ContractStatus    = $contractStatus
        PullRequestGate   = $pullRequestGate
    }
}

function Get-ToiNextActions {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Snapshot
    )

    $nextActions = New-Object System.Collections.Generic.List[string]

    if ($Snapshot.Status.Unstaged -gt 0 -or $Snapshot.Status.Untracked -gt 0) {
        $nextActions.Add('Clean up or checkpoint the working tree with `.\\toi.ps1 save`.')
    }

    if ($Snapshot.Branch -ne $Snapshot.DefaultBranch -and -not $Snapshot.Published) {
        $nextActions.Add('Publish the branch with `.\\toi.ps1 publish` when it is ready.')
    }

    if ($Snapshot.Branch -ne $Snapshot.DefaultBranch -and $Snapshot.Published) {
        if ($Snapshot.PullRequestGate -and $Snapshot.PullRequestGate.recommended_command) {
            $nextActions.Add("PR next step: $($Snapshot.PullRequestGate.recommended_command)")
        }
        else {
            $nextActions.Add('Open the PR path with `.\\toi.ps1 open pr`.')
        }
    }

    if ($Snapshot.Branch -eq $Snapshot.DefaultBranch -and $Snapshot.Status.ChangedFiles -eq 0) {
        $nextActions.Add('Create a typed branch with `.\\toi.ps1 start feature <name>` for the next change.')
    }

    if ($Snapshot.RequireBranchNote -and $Snapshot.Branch -ne $Snapshot.DefaultBranch -and -not $Snapshot.Note) {
        $nextActions.Add('Add a branch note with `.\\toi.ps1 note set <text>`.')
    }

    if ($Snapshot.UpstreamTracking -and $Snapshot.UpstreamTracking.RightAhead -gt 0) {
        $nextActions.Add('Sync the branch with `.\\toi.ps1 sync` before pushing or opening a PR.')
    }

    if ($Snapshot.DefaultTracking -and $Snapshot.DefaultTracking.RightAhead -gt 0) {
        $nextActions.Add("Restack or rebase on $($Snapshot.DefaultBranch) to pick up newer commits.")
    }

    if (-not $Snapshot.ContractStatus.SnapshotMatches) {
        $nextActions.Add('Refresh the committed contract snapshot with `.\\toi.ps1 schema -WriteSnapshot`.')
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
        contract = [PSCustomObject]@{
            version = $Snapshot.ContractStatus.Version
            snapshot_matches = $Snapshot.ContractStatus.SnapshotMatches
            reason = $Snapshot.ContractStatus.Reason
            path = $Snapshot.ContractStatus.SnapshotPath
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
        $recommendations.Add("Avoid doing feature work directly on '$($Snapshot.Branch)'. Create a branch with `.\\toi.ps1 start feature <name>`.")
    }

    if ($Snapshot.RequireBranchNote -and $Snapshot.Branch -ne $Snapshot.DefaultBranch -and -not $Snapshot.Note) {
        $recommendations.Add('Add a branch note with `.\\toi.ps1 note set <text>`.')
    }

    if ($Snapshot.UpstreamTracking) {
        if ($Snapshot.UpstreamTracking.RightAhead -gt 0) {
            $recommendations.Add('Run `.\\toi.ps1 sync` before pushing or opening a PR.')
        }

        if ($Snapshot.UpstreamTracking.LeftAhead -gt 0) {
            $recommendations.Add('Branch has local commits ready to push or review.')
        }
    }
    elseif ($Snapshot.Branch -ne $Snapshot.DefaultBranch) {
        $recommendations.Add('Run `.\\toi.ps1 publish` when this branch is ready for review.')
    }

    if ($Snapshot.DefaultTracking -and $Snapshot.DefaultTracking.RightAhead -gt 0) {
        $recommendations.Add('Rebase or sync against the default branch before shipping.')
    }

    if ($Snapshot.UpstreamRef -and $Snapshot.DefaultTracking -and $Snapshot.DefaultTracking.LeftAhead -gt 0) {
        $recommendations.Add('Open a PR with `.\\toi.ps1 open pr` when the branch is ready.')
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
        $notes.Add('Use `.\\toi.ps1 save` or commit/stage intentionally first.')
    }

    if (-not (Test-MatchesBranchConvention -BranchName $Snapshot.Branch) -and $Snapshot.ProtectedBranches -notcontains $Snapshot.Branch) {
        $notes.Add('Branch name is outside .\\toi.ps1 conventions.')
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
        $notes.Add('Branch is local only. Run `.\\toi.ps1 publish` to push it and set upstream.')
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
        contract = [PSCustomObject]@{
            version = $snapshot.ContractStatus.Version
            snapshot_matches = $snapshot.ContractStatus.SnapshotMatches
            reason = $snapshot.ContractStatus.Reason
            path = $snapshot.ContractStatus.SnapshotPath
        }
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
    $lines.Add('## Contracts')
    $lines.Add('')
    $lines.Add("- Version: $($Report.contract.version)")
    $lines.Add("- Snapshot matches: $($Report.contract.snapshot_matches)")
    $lines.Add("- Snapshot path: $($Report.contract.path)")
    $lines.Add("- Status: $($Report.contract.reason)")
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
    $versionPath = Join-Path (Get-RepositoryRoot) 'contracts\contract-version.txt'

    if (-not (Test-Path -LiteralPath $versionPath)) {
        return '1.0.0'
    }

    $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
    if (-not $version) {
        throw 'contracts/contract-version.txt is empty.'
    }

    return $version
}

function Test-ToiValidContractVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    return $Version -match '^\d+\.\d+\.\d+$'
}

function Get-ToiContractSnapshotPath {
    return (Join-Path (Get-RepositoryRoot) 'contracts\toi-schema.json')
}

function Set-ToiContractVersion {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    if (-not (Test-ToiValidContractVersion -Version $Version)) {
        throw "Invalid contract version '$Version'. Expected semantic versioning like 1.2.3."
    }

    $versionPath = Join-Path (Get-RepositoryRoot) 'contracts\contract-version.txt'
    $directory = Split-Path -Parent $versionPath
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Set-Content -LiteralPath $versionPath -Value $Version
    return $versionPath
}

function Get-ToiNextContractVersion {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('major', 'minor', 'patch')]
        [string]$Bump
    )

    $current = Get-ToiContractVersion
    if ($current -notmatch '^(\d+)\.(\d+)\.(\d+)$') {
        throw "Invalid contract version '$current'. Expected semantic versioning like 1.2.3."
    }

    $major = [int]$matches[1]
    $minor = [int]$matches[2]
    $patch = [int]$matches[3]

    switch ($Bump) {
        'major' {
            $major++
            $minor = 0
            $patch = 0
        }
        'minor' {
            $minor++
            $patch = 0
        }
        'patch' {
            $patch++
        }
    }

    return "$major.$minor.$patch"
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

function New-ToiObjectSchema {
    param(
        [string]$Description,
        [string[]]$Required,
        [hashtable]$Properties
    )

    $propertyBag = [ordered]@{}
    foreach ($key in $Properties.Keys) {
        $propertyBag[$key] = $Properties[$key]
    }

    return [PSCustomObject]@{
        type = 'object'
        description = $Description
        required = @($Required)
        properties = [PSCustomObject]$propertyBag
    }
}

function New-ToiArraySchema {
    param(
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [psobject]$Items
    )

    return [PSCustomObject]@{
        type = 'array'
        description = $Description
        items = $Items
    }
}

function Get-ToiJsonCommandSchemas {
    $stringField = New-ToiSchemaField -Type 'string'
    $booleanField = New-ToiSchemaField -Type 'boolean'
    $numberField = New-ToiSchemaField -Type 'number'
    $stringArray = New-ToiArraySchema -Description 'Array of strings.' -Items $stringField
    $qualityGateResultSchema = New-ToiObjectSchema -Description 'Validation command result.' -Required @('command', 'success', 'exit_code') -Properties @{
        command = (New-ToiSchemaField -Type 'string' -Description 'Validation command text.')
        success = (New-ToiSchemaField -Type 'boolean' -Description 'Whether the validation command succeeded.')
        exit_code = (New-ToiSchemaField -Type 'number' -Description 'Validation command exit code.')
    }
    $qualityGateArray = New-ToiArraySchema -Description 'Array of quality gate results.' -Items $qualityGateResultSchema
    $branchSchema = New-ToiObjectSchema -Description 'Branch-level workflow metadata.' -Required @('current', 'type', 'default', 'published', 'note', 'commit_convention') -Properties @{
        current = (New-ToiSchemaField -Type 'string' -Description 'Current branch name.')
        type = (New-ToiSchemaField -Type 'string|null' -Description 'Detected .\\toi.ps1 branch type.')
        default = (New-ToiSchemaField -Type 'string' -Description 'Configured default branch name.')
        published = (New-ToiSchemaField -Type 'boolean' -Description 'Whether the current branch exists on a remote.')
        note = (New-ToiSchemaField -Type 'string|null' -Description 'Local branch note, if present.')
        commit_convention = (New-ToiSchemaField -Type 'string' -Description 'Configured commit convention mode.')
    }
    $workingTreeSchema = New-ToiObjectSchema -Description 'Working tree counts.' -Required @('changed_files', 'staged', 'unstaged', 'untracked') -Properties @{
        changed_files = (New-ToiSchemaField -Type 'number' -Description 'Changed file count.')
        staged = (New-ToiSchemaField -Type 'number' -Description 'Staged file count.')
        unstaged = (New-ToiSchemaField -Type 'number' -Description 'Unstaged file count.')
        untracked = (New-ToiSchemaField -Type 'number' -Description 'Untracked file count.')
    }
    $publishSchema = New-ToiObjectSchema -Description 'Publish/upstream status.' -Required @('upstream', 'ahead', 'behind') -Properties @{
        upstream = (New-ToiSchemaField -Type 'string|null' -Description 'Configured upstream ref, if present.')
        ahead = (New-ToiSchemaField -Type 'number|null' -Description 'Commits ahead of upstream.')
        behind = (New-ToiSchemaField -Type 'number|null' -Description 'Commits behind upstream.')
    }
    $stackSchema = New-ToiObjectSchema -Description 'Stack-parent and default-branch comparison state.' -Required @('parent', 'behind_default') -Properties @{
        parent = (New-ToiSchemaField -Type 'string|null' -Description 'Recorded stack parent branch.')
        behind_default = (New-ToiSchemaField -Type 'number|null' -Description 'Commits behind the default branch.')
    }
    $qualityGatesSchema = New-ToiObjectSchema -Description 'Configured validation mode and latest results.' -Required @('mode', 'has_checks', 'results') -Properties @{
        mode = (New-ToiSchemaField -Type 'string' -Description 'Validation mode.')
        has_checks = (New-ToiSchemaField -Type 'boolean' -Description 'Whether validation commands are configured.')
        results = $qualityGateArray
    }
    $policySchema = New-ToiObjectSchema -Description 'Active workflow policy flags.' -Required @('require_branch_note') -Properties @{
        require_branch_note = (New-ToiSchemaField -Type 'boolean' -Description 'Whether non-default branches require a local note.')
    }
    $contractSchema = New-ToiObjectSchema -Description 'Contract snapshot status.' -Required @('version', 'snapshot_matches', 'reason', 'path') -Properties @{
        version = (New-ToiSchemaField -Type 'string' -Description 'Current contract version.')
        snapshot_matches = (New-ToiSchemaField -Type 'boolean' -Description 'Whether the committed snapshot matches the current contract output.')
        reason = (New-ToiSchemaField -Type 'string' -Description 'Human-readable contract status.')
        path = (New-ToiSchemaField -Type 'string' -Description 'Path to the committed contract snapshot.')
    }
    $doctorSchema = New-ToiObjectSchema -Description 'Doctor recommendations.' -Required @('recommendations') -Properties @{
        recommendations = $stringArray
    }
    $shipAssessmentSchema = New-ToiObjectSchema -Description 'Shipping assessment.' -Required @('blocking_issues', 'notes', 'commit_range', 'shippable') -Properties @{
        blocking_issues = $stringArray
        notes = $stringArray
        commit_range = $stringArray
        shippable = (New-ToiSchemaField -Type 'boolean' -Description 'Whether the branch is shippable.')
    }
    $selfCheckResultSchema = New-ToiObjectSchema -Description 'Per-check result.' -Required @('name', 'success', 'detail') -Properties @{
        name = $stringField
        success = $booleanField
        detail = $stringField
    }
    $selfCheckSummarySchema = New-ToiObjectSchema -Description 'Aggregate pass/fail counts.' -Required @('checks', 'passed', 'failed') -Properties @{
        checks = $numberField
        passed = $numberField
        failed = $numberField
    }
    $snapshotSchema = New-ToiObjectSchema -Description 'Workflow snapshot model.' -Required @('branch', 'working_tree', 'publish', 'stack', 'quality_gates', 'policy', 'contract') -Properties @{
        branch = $branchSchema
        working_tree = $workingTreeSchema
        publish = $publishSchema
        stack = $stackSchema
        quality_gates = $qualityGatesSchema
        policy = $policySchema
        contract = $contractSchema
    }
    $prCheckSchema = New-ToiObjectSchema -Description 'Single pull request check result.' -Required @('bucket', 'name', 'state', 'workflow') -Properties @{
        bucket = New-ToiSchemaField -Type 'string' -Description 'Check status bucket.'
        name = New-ToiSchemaField -Type 'string' -Description 'Check name.'
        state = New-ToiSchemaField -Type 'string|null' -Description 'Raw GitHub check state.'
        workflow = New-ToiSchemaField -Type 'string|null' -Description 'Workflow name, if available.'
        link = New-ToiSchemaField -Type 'string|null' -Description 'Web URL for the check.'
        description = New-ToiSchemaField -Type 'string|null' -Description 'Check description.'
        event = New-ToiSchemaField -Type 'string|null' -Description 'Triggering event.'
        startedAt = New-ToiSchemaField -Type 'string|null' -Description 'Start timestamp.'
        completedAt = New-ToiSchemaField -Type 'string|null' -Description 'Completion timestamp.'
    }
    $prChecksSummarySchema = New-ToiObjectSchema -Description 'Summary of PR checks by bucket.' -Required @('pass', 'fail', 'pending', 'cancel', 'skipping') -Properties @{
        pass = $numberField
        fail = $numberField
        pending = $numberField
        cancel = $numberField
        skipping = $numberField
    }
    $prReviewSummarySchema = New-ToiObjectSchema -Description 'Summary of latest PR reviews by state.' -Required @('approved', 'changes_requested', 'commented') -Properties @{
        approved = $numberField
        changes_requested = $numberField
        commented = $numberField
    }

    return [PSCustomObject]@{
        status = (New-ToiObjectSchema -Description 'Status command JSON output.' -Required @('branch', 'published', 'upstream', 'branch_line', 'staged', 'unstaged', 'untracked') -Properties @{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                published = New-ToiSchemaField -Type 'boolean' -Description 'Whether the current branch exists on a remote.'
                upstream = New-ToiSchemaField -Type 'string|null' -Description 'Configured upstream ref, if present.'
                branch_line = New-ToiSchemaField -Type 'string' -Description 'Raw `git status --short --branch` headline.'
                staged = $stringArray
                unstaged = $stringArray
                untracked = $stringArray
            })
        dashboard = (New-ToiObjectSchema -Description 'Dashboard command JSON output.' -Required @('branch', 'working_tree', 'publish', 'stack', 'quality_gates', 'policy', 'contract', 'next_actions') -Properties @{
                branch = $branchSchema
                working_tree = $workingTreeSchema
                publish = $publishSchema
                stack = $stackSchema
                quality_gates = $qualityGatesSchema
                policy = $policySchema
                contract = $contractSchema
                next_actions = $stringArray
            })
        next = (New-ToiObjectSchema -Description 'Next command JSON output.' -Required @('branch', 'message', 'published', 'contract_version', 'contract_snapshot_matches') -Properties @{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                message = New-ToiSchemaField -Type 'string' -Description 'Single recommended next action.'
                published = New-ToiSchemaField -Type 'boolean' -Description 'Whether the branch is published.'
                contract_version = New-ToiSchemaField -Type 'string' -Description 'Current contract version.'
                contract_snapshot_matches = New-ToiSchemaField -Type 'boolean' -Description 'Whether the committed contract snapshot matches current output.'
            })
        doctor = (New-ToiObjectSchema -Description 'Doctor command JSON output.' -Required @('branch', 'working_tree', 'publish', 'stack', 'quality_gates', 'policy', 'contract', 'recommendations') -Properties @{
                branch = $branchSchema
                working_tree = $workingTreeSchema
                publish = $publishSchema
                stack = $stackSchema
                quality_gates = $qualityGatesSchema
                policy = $policySchema
                contract = $contractSchema
                recommendations = $stringArray
            })
        ship = (New-ToiObjectSchema -Description 'Ship command JSON output.' -Required @('branch', 'working_tree', 'publish', 'stack', 'quality_gates', 'policy', 'contract', 'ship') -Properties @{
                branch = $branchSchema
                working_tree = $workingTreeSchema
                publish = $publishSchema
                stack = $stackSchema
                quality_gates = $qualityGatesSchema
                policy = $policySchema
                contract = $contractSchema
                ship = $shipAssessmentSchema
            })
        publish = [PSCustomObject]@{
            type = 'object'
            description = 'Publish command JSON output.'
            required = @('branch', 'dry_run', 'quality_gate_mode', 'upstream', 'branch_url', 'pr_url', 'github_cli', 'push_output', 'quality_gates')
            properties = [PSCustomObject]@{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                dry_run = New-ToiSchemaField -Type 'boolean' -Description 'Whether publish ran in dry-run mode.'
                quality_gate_mode = New-ToiSchemaField -Type 'string' -Description 'Configured quality gate mode.'
                upstream = New-ToiSchemaField -Type 'string|null' -Description 'Configured upstream ref before push.'
                branch_url = New-ToiSchemaField -Type 'string' -Description 'GitHub branch URL.'
                pr_url = New-ToiSchemaField -Type 'string' -Description 'GitHub compare/PR URL.'
                github_cli = New-ToiSchemaField -Type 'boolean' -Description 'Whether gh.exe is available on PATH.'
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
        pr = (New-ToiObjectSchema -Description 'PR status command JSON output.' -Required @('number', 'title', 'url', 'state', 'isDraft', 'reviewDecision', 'mergeStateStatus', 'headRefName', 'baseRefName') -Properties @{
                number = New-ToiSchemaField -Type 'number' -Description 'Pull request number.'
                title = New-ToiSchemaField -Type 'string' -Description 'Pull request title.'
                url = New-ToiSchemaField -Type 'string' -Description 'Pull request URL.'
                state = New-ToiSchemaField -Type 'string' -Description 'Pull request state.'
                isDraft = New-ToiSchemaField -Type 'boolean' -Description 'Whether the pull request is a draft.'
                reviewDecision = New-ToiSchemaField -Type 'string|null' -Description 'GitHub review decision.'
                mergeStateStatus = New-ToiSchemaField -Type 'string|null' -Description 'GitHub merge state status.'
                headRefName = New-ToiSchemaField -Type 'string' -Description 'Head branch name.'
                baseRefName = New-ToiSchemaField -Type 'string' -Description 'Base branch name.'
                reviewRequests = New-ToiArraySchema -Description 'Raw GitHub review request payloads.' -Items (New-ToiSchemaField -Type 'object' -Description 'Review request item.')
                latestReviews = New-ToiArraySchema -Description 'Raw GitHub latest review payloads.' -Items (New-ToiSchemaField -Type 'object' -Description 'Latest review item.')
            })
        pr_checks = (New-ToiObjectSchema -Description 'PR checks command JSON output.' -Required @('branch', 'required', 'summary', 'checks') -Properties @{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                required = New-ToiSchemaField -Type 'boolean' -Description 'Whether only required checks were requested.'
                summary = $prChecksSummarySchema
                checks = (New-ToiArraySchema -Description 'Array of PR checks.' -Items $prCheckSchema)
            })
        pr_ready = (New-ToiObjectSchema -Description 'PR ready command JSON output.' -Required @('branch', 'dry_run', 'undo', 'command', 'output') -Properties @{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                dry_run = New-ToiSchemaField -Type 'boolean' -Description 'Whether the ready command was a dry run.'
                undo = New-ToiSchemaField -Type 'boolean' -Description 'Whether the command would mark the PR as draft.'
                command = $stringArray
                output = $stringArray
            })
        pr_merge = (New-ToiObjectSchema -Description 'PR merge command JSON output.' -Required @('branch', 'dry_run', 'strategy', 'auto', 'admin', 'delete_branch', 'command', 'output') -Properties @{
                branch = New-ToiSchemaField -Type 'string' -Description 'Current branch name.'
                dry_run = New-ToiSchemaField -Type 'boolean' -Description 'Whether the merge command was a dry run.'
                strategy = New-ToiSchemaField -Type 'string' -Description 'Requested merge strategy.'
                auto = New-ToiSchemaField -Type 'boolean' -Description 'Whether auto-merge was requested.'
                admin = New-ToiSchemaField -Type 'boolean' -Description 'Whether admin merge privileges were requested.'
                delete_branch = New-ToiSchemaField -Type 'boolean' -Description 'Whether the branch should be deleted after merge.'
                command = $stringArray
                output = $stringArray
            })
        pr_gate = (New-ToiObjectSchema -Description 'PR gate command JSON output.' -Required @('ready', 'branch', 'title', 'url', 'draft', 'state', 'review_decision', 'merge_state', 'requested_reviewers', 'reviews', 'checks', 'recommended_action', 'recommended_command', 'blockers', 'warnings') -Properties @{
                ready = New-ToiSchemaField -Type 'boolean' -Description 'Whether the PR appears ready to merge.'
                branch = New-ToiSchemaField -Type 'string' -Description 'Head branch name.'
                title = New-ToiSchemaField -Type 'string' -Description 'Pull request title.'
                url = New-ToiSchemaField -Type 'string' -Description 'Pull request URL.'
                draft = New-ToiSchemaField -Type 'boolean' -Description 'Whether the PR is still a draft.'
                state = New-ToiSchemaField -Type 'string' -Description 'Pull request state.'
                review_decision = New-ToiSchemaField -Type 'string|null' -Description 'GitHub review decision.'
                merge_state = New-ToiSchemaField -Type 'string|null' -Description 'GitHub merge state.'
                requested_reviewers = $stringArray
                reviews = $prReviewSummarySchema
                checks = $prChecksSummarySchema
                recommended_action = New-ToiSchemaField -Type 'string' -Description 'Suggested next step for the PR.'
                recommended_command = New-ToiSchemaField -Type 'string' -Description 'Suggested TOI command for the next step.'
                blockers = $stringArray
                warnings = $stringArray
            })
        review = (New-ToiObjectSchema -Description 'Review command JSON output.' -Required @('title', 'branch', 'url', 'review_decision', 'requested_reviewers', 'reviews', 'latest_reviews', 'ready', 'recommended_action', 'recommended_command', 'blockers', 'warnings') -Properties @{
                title = New-ToiSchemaField -Type 'string' -Description 'Pull request title.'
                branch = New-ToiSchemaField -Type 'string' -Description 'Head branch name.'
                url = New-ToiSchemaField -Type 'string' -Description 'Pull request URL.'
                review_decision = New-ToiSchemaField -Type 'string|null' -Description 'GitHub review decision.'
                requested_reviewers = $stringArray
                reviews = $prReviewSummarySchema
                latest_reviews = (New-ToiArraySchema -Description 'Latest review details.' -Items (New-ToiObjectSchema -Description 'Latest review item.' -Required @('reviewer', 'state') -Properties @{
                            reviewer = New-ToiSchemaField -Type 'string' -Description 'Reviewer display name.'
                            state = New-ToiSchemaField -Type 'string|null' -Description 'Latest review state.'
                        }))
                ready = New-ToiSchemaField -Type 'boolean' -Description 'Whether the PR appears ready to merge.'
                recommended_action = New-ToiSchemaField -Type 'string' -Description 'Suggested next step for the PR.'
                recommended_command = New-ToiSchemaField -Type 'string' -Description 'Suggested TOI command for the next step.'
                blockers = $stringArray
                warnings = $stringArray
            })
        self_check = (New-ToiObjectSchema -Description 'Self-check command JSON output.' -Required @('checks', 'summary') -Properties @{
                checks = (New-ToiArraySchema -Description 'Per-check results.' -Items $selfCheckResultSchema)
                summary = $selfCheckSummarySchema
            })
        report = (New-ToiObjectSchema -Description 'Report command JSON output.' -Required @('generated_at', 'snapshot', 'next_actions', 'contract', 'doctor', 'ship') -Properties @{
                generated_at = New-ToiSchemaField -Type 'string' -Description 'Local timestamp when the report was generated.'
                snapshot = $snapshotSchema
                next_actions = $stringArray
                contract = $contractSchema
                doctor = $doctorSchema
                ship = $shipAssessmentSchema
            })
    }
}

function Get-ToiSchemaModel {
    return [PSCustomObject]@{
        contract_version = Get-ToiContractVersion
        generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        commands = Get-ToiJsonCommandSchemas
    }
}

function Get-ToiSchemaSnapshotModel {
    return [PSCustomObject]@{
        contract_version = Get-ToiContractVersion
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

function Test-ToiValueMatchesSchemaType {
    param(
        [object]$Value,
        [Parameter(Mandatory = $true)]
        [string]$Type
    )

    switch ($Type) {
        'string' { return $Value -is [string] }
        'boolean' { return $Value -is [bool] }
        'number' { return $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal] }
        'object' { return $null -ne $Value -and $Value -isnot [string] -and $Value -isnot [System.Array] -and $Value.PSObject -and $Value.PSObject.Properties.Count -ge 0 }
        'array' { return $Value -is [System.Array] }
        'null' { return $null -eq $Value }
        default { return $false }
    }
}

function Get-ToiSchemaValidationErrors {
    param(
        [object]$Value,
        [Parameter(Mandatory = $true)]
        [psobject]$Schema,
        [string]$Path = '$'
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $types = @()
    if ($Schema.type) {
        $types = @(([string]$Schema.type) -split '\|')
    }

    $matchesAnyType = $false
    foreach ($candidateType in $types) {
        if (Test-ToiValueMatchesSchemaType -Value $Value -Type $candidateType) {
            $matchesAnyType = $true
            break
        }
    }

    if (-not $matchesAnyType) {
        $errors.Add("$Path expected type '$($Schema.type)'.")
        return @($errors)
    }

    if ($null -eq $Value) {
        return @($errors)
    }

    if ($types -contains 'object' -and $Schema.required) {
        foreach ($requiredField in $Schema.required) {
            if (-not ($Value.PSObject.Properties.Name -contains $requiredField)) {
                $errors.Add("$Path missing required field '$requiredField'.")
            }
        }
    }

    if ($types -contains 'object' -and $Schema.properties) {
        foreach ($property in $Schema.properties.PSObject.Properties) {
            if ($Value.PSObject.Properties.Name -contains $property.Name) {
                $childErrors = Get-ToiSchemaValidationErrors -Value $Value.$($property.Name) -Schema $property.Value -Path "$Path.$($property.Name)"
                foreach ($childError in $childErrors) {
                    $errors.Add($childError)
                }
            }
        }
    }

    if ($types -contains 'array' -and $Schema.items -and $Value -is [System.Array]) {
        for ($index = 0; $index -lt $Value.Count; $index++) {
            $childErrors = Get-ToiSchemaValidationErrors -Value $Value[$index] -Schema $Schema.items -Path "$Path[$index]"
            foreach ($childError in $childErrors) {
                $errors.Add($childError)
            }
        }
    }

    return @($errors)
}

function Convert-ToiValueToCanonicalForm {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64] -or $Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return $Value
    }

    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { Convert-ToiValueToCanonicalForm -Value $_ })
    }

    $ordered = [ordered]@{}
    foreach ($property in ($Value.PSObject.Properties | Sort-Object Name)) {
        $ordered[$property.Name] = Convert-ToiValueToCanonicalForm -Value $property.Value
    }

    return [PSCustomObject]$ordered
}

function Convert-ToiValueToCanonicalJson {
    param(
        [object]$Value
    )

    $canonical = Convert-ToiValueToCanonicalForm -Value $Value
    return ($canonical | ConvertTo-Json -Depth 64)
}

function Test-ToiContractSnapshotMatchesCurrent {
    $snapshotPath = Get-ToiContractSnapshotPath
    if (-not (Test-Path -LiteralPath $snapshotPath)) {
        return [PSCustomObject]@{
            matches = $false
            reason = 'contracts/toi-schema.json is missing.'
            path = $snapshotPath
            contract_version = Get-ToiContractVersion
        }
    }

    $expectedSnapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    $currentSnapshot = Get-ToiSchemaSnapshotModel
    $expectedCanonical = Convert-ToiValueToCanonicalJson -Value $expectedSnapshot
    $currentCanonical = Convert-ToiValueToCanonicalJson -Value $currentSnapshot

    return [PSCustomObject]@{
        matches = ($expectedCanonical -eq $currentCanonical)
        reason = if ($expectedCanonical -eq $currentCanonical) { 'Committed schema snapshot matches current contract output.' } else { 'Committed contract snapshot is out of date. Regenerate contracts/toi-schema.json.' }
        path = $snapshotPath
        contract_version = Get-ToiContractVersion
    }
}

function Get-ToiContractStatus {
    $status = Test-ToiContractSnapshotMatchesCurrent

    return [PSCustomObject]@{
        Version = $status.contract_version
        SnapshotMatches = $status.matches
        SnapshotPath = $status.path
        Reason = $status.reason
    }
}

