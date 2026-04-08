function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $action = 'install'
    $mode = 'profile'
    $dryRun = $false
    $targetDir = $null
    $profilePath = $null

    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]

        switch -Regex ($argument) {
            '^(status)$' {
                $action = 'status'
                continue
            }
            '^(uninstall)$' {
                $action = 'uninstall'
                continue
            }
            '^(profile|user-bin|module)$' {
                $mode = $argument.ToLowerInvariant()
                continue
            }
            '^-DryRun$' {
                $dryRun = $true
                continue
            }
            '^-TargetDir$' {
                if ($index + 1 -ge $Arguments.Count) {
                    throw 'Expected a directory path after -TargetDir.'
                }

                $index++
                $targetDir = $Arguments[$index]
                continue
            }
            '^-ProfilePath$' {
                if ($index + 1 -ge $Arguments.Count) {
                    throw 'Expected a file path after -ProfilePath.'
                }

                $index++
                $profilePath = $Arguments[$index]
                continue
            }
            default {
                throw "Unknown install argument: $argument"
            }
        }
    }

    $repoRoot = Get-RepositoryRoot
    $toiPath = Join-Path $repoRoot 'toi.ps1'
    $moduleName = 'TOIGit'
    $moduleVersion = (Import-PowerShellDataFile -LiteralPath (Join-Path $repoRoot 'TOIGit.psd1')).ModuleVersion
    $beginMarker = '# >>> TOI Git >>>'
    $endMarker = '# <<< TOI Git <<<'

    function Get-InstallSnippet {
        return @(
            $beginMarker
            'function toi {'
            '    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)'
            "    & '$toiPath' @Args"
            '}'
            $endMarker
        ) -join [Environment]::NewLine
    }

    function Get-ResolvedProfilePath {
        if ($profilePath) {
            return $profilePath
        }

        $currentHostProfile = $PROFILE.CurrentUserCurrentHost
        $allHostsProfile = $PROFILE.CurrentUserAllHosts

        if ((Test-Path -LiteralPath $currentHostProfile) -and (Test-ProfileHasSignatureBlock -Path $currentHostProfile)) {
            if ($allHostsProfile -and -not [string]::Equals($currentHostProfile, $allHostsProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $allHostsProfile
            }
        }

        return $PROFILE.CurrentUserCurrentHost
    }

    function Test-ProfileHasSignatureBlock {
        param([string]$Path)

        if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
            return $false
        }

        $content = Get-Content -LiteralPath $Path -Raw
        return $content -match '(?m)^# SIG # Begin signature block'
    }

    function Get-UserBinDirectory {
        if ($targetDir) {
            return $targetDir
        }

        return (Join-Path $HOME 'bin')
    }

    function Get-UserModuleRoot {
        $documentsDirectory = [Environment]::GetFolderPath('MyDocuments')
        $moduleRoot = if ($PSEdition -eq 'Core') {
            Join-Path $documentsDirectory 'PowerShell\Modules'
        }
        else {
            Join-Path $documentsDirectory 'WindowsPowerShell\Modules'
        }

        if ($targetDir) {
            return $targetDir
        }

        return $moduleRoot
    }

    function Get-ModuleInstallDirectory {
        return (Join-Path (Get-UserModuleRoot) $moduleName)
    }

    function Get-ManagedModuleItems {
        return @(
            'toi.ps1',
            'toi.cmd',
            'toi.json',
            'TOIGit.psm1',
            'TOIGit.psd1',
            'commands',
            'lib',
            'contracts'
        )
    }

    function Test-PathContainsDirectory {
        param([string]$Directory)

        if (-not $Directory) {
            return $false
        }

        $pathEntries = @($env:PATH -split ';' | Where-Object { $_ -and $_.Trim() })
        foreach ($entry in $pathEntries) {
            if ([string]::Equals(
                    ([System.IO.Path]::GetFullPath($entry.TrimEnd('\'))),
                    ([System.IO.Path]::GetFullPath($Directory.TrimEnd('\'))),
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    }

    function Test-ModulePathContainsDirectory {
        param([string]$Directory)

        if (-not $Directory) {
            return $false
        }

        $entries = @($env:PSModulePath -split ';' | Where-Object { $_ -and $_.Trim() })
        foreach ($entry in $entries) {
            if ([string]::Equals(
                    ([System.IO.Path]::GetFullPath($entry.TrimEnd('\'))),
                    ([System.IO.Path]::GetFullPath($Directory.TrimEnd('\'))),
                    [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    }

    function Test-ProfileInstalled {
        $resolvedProfilePath = Get-ResolvedProfilePath
        if (-not (Test-Path -LiteralPath $resolvedProfilePath)) {
            return $false
        }

        $content = Get-Content -LiteralPath $resolvedProfilePath -Raw
        return ($content -match ([regex]::Escape($beginMarker) + '.*?' + [regex]::Escape($endMarker)))
    }

    function Test-UserBinInstalled {
        $resolvedTargetDir = Get-UserBinDirectory
        $launcherPath = Join-Path $resolvedTargetDir 'toi.ps1'
        $cmdLauncherPath = Join-Path $resolvedTargetDir 'toi.cmd'
        return (Test-Path -LiteralPath $launcherPath) -and (Test-Path -LiteralPath $cmdLauncherPath)
    }

    function Test-ModuleInstalled {
        $moduleDirectory = Get-ModuleInstallDirectory
        $manifestPath = Join-Path $moduleDirectory 'TOIGit.psd1'
        $entryPointPath = Join-Path $moduleDirectory 'toi.ps1'
        return (Test-Path -LiteralPath $manifestPath) -and (Test-Path -LiteralPath $entryPointPath)
    }

    function Remove-ProfileInstall {
        $resolvedProfilePath = Get-ResolvedProfilePath
        if (-not (Test-Path -LiteralPath $resolvedProfilePath)) {
            Write-Section 'Install'
            Write-WarningLine 'PowerShell profile does not exist.'
            return
        }

        $existingContent = Get-Content -LiteralPath $resolvedProfilePath -Raw
        $pattern = [regex]::Escape($beginMarker) + '.*?' + [regex]::Escape($endMarker) + '\s*'
        if ($existingContent -notmatch $pattern) {
            Write-Section 'Install'
            Write-WarningLine 'TOI Git profile snippet was not found.'
            return
        }

        if ($dryRun) {
            Write-Section 'Install'
            Write-InfoLine 'Action: uninstall'
            Write-InfoLine 'Mode: profile'
            Write-InfoLine "Profile path: $resolvedProfilePath"
            Write-InfoLine 'Dry run: True'
            return
        }

        $updatedContent = [regex]::Replace($existingContent, $pattern, '', [System.Text.RegularExpressions.RegexOptions]::Singleline).TrimEnd()
        if ($updatedContent) {
            Set-Content -LiteralPath $resolvedProfilePath -Value ($updatedContent + [Environment]::NewLine)
        }
        else {
            Clear-Content -LiteralPath $resolvedProfilePath
        }

        Write-Section 'Install'
        Write-SuccessLine 'Removed TOI Git from your PowerShell profile.'
        Write-InfoLine "Profile path: $resolvedProfilePath"
    }

    function Set-ProfileInstall {
        $resolvedProfilePath = Get-ResolvedProfilePath
        $snippet = Get-InstallSnippet
        $existingContent = ''
        $currentHostProfile = $PROFILE.CurrentUserCurrentHost
        $fellBackFromSignedProfile = $false

        if (-not $profilePath -and $currentHostProfile -and (Test-Path -LiteralPath $currentHostProfile) -and (Test-ProfileHasSignatureBlock -Path $currentHostProfile) -and
            -not [string]::Equals($resolvedProfilePath, $currentHostProfile, [System.StringComparison]::OrdinalIgnoreCase)) {
            $fellBackFromSignedProfile = $true
        }

        if (Test-Path -LiteralPath $resolvedProfilePath) {
            $existingContent = Get-Content -LiteralPath $resolvedProfilePath -Raw
        }

        if (Test-ProfileHasSignatureBlock -Path $resolvedProfilePath) {
            throw "Profile '$resolvedProfilePath' contains a signature block. TOI Git will not modify signed profiles. Use '.\\toi.ps1 install module', '.\\toi.ps1 install user-bin', or choose an unsigned profile path with -ProfilePath."
        }

        $pattern = [regex]::Escape($beginMarker) + '.*?' + [regex]::Escape($endMarker)
        $updatedContent = if ($existingContent -match $pattern) {
            [regex]::Replace($existingContent, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $snippet }, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        }
        elseif ([string]::IsNullOrWhiteSpace($existingContent)) {
            $snippet + [Environment]::NewLine
        }
        else {
            $existingContent.TrimEnd() + [Environment]::NewLine + [Environment]::NewLine + $snippet + [Environment]::NewLine
        }

        if ($dryRun) {
            Write-Section 'Install'
            Write-InfoLine 'Mode: profile'
            Write-InfoLine "Profile path: $resolvedProfilePath"
            if ($fellBackFromSignedProfile) {
                Write-WarningLine "Detected a signed current-host profile at '$currentHostProfile'. Using CurrentUserAllHosts instead."
            }
            Write-InfoLine 'Dry run: True'
            Write-Host ''
            Write-Host $snippet
            return
        }

        $profileDirectory = Split-Path -Parent $resolvedProfilePath
        if ($profileDirectory -and -not (Test-Path -LiteralPath $profileDirectory)) {
            New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        }

        Set-Content -LiteralPath $resolvedProfilePath -Value $updatedContent

        Write-Section 'Install'
        Write-SuccessLine 'Installed TOI Git into your PowerShell profile.'
        Write-InfoLine "Profile path: $resolvedProfilePath"
        if ($fellBackFromSignedProfile) {
            Write-WarningLine "Detected a signed current-host profile at '$currentHostProfile'. Installed TOI into CurrentUserAllHosts instead."
        }
        Write-InfoLine 'Open a new shell or run: . $PROFILE'
        Write-InfoLine 'Then you can use: toi status'
    }

    function Remove-UserBinInstall {
        $resolvedTargetDir = Get-UserBinDirectory
        $launcherPath = Join-Path $resolvedTargetDir 'toi.ps1'
        $cmdLauncherPath = Join-Path $resolvedTargetDir 'toi.cmd'

        if ($dryRun) {
            Write-Section 'Install'
            Write-InfoLine 'Action: uninstall'
            Write-InfoLine 'Mode: user-bin'
            Write-InfoLine "Target directory: $resolvedTargetDir"
            Write-InfoLine 'Dry run: True'
            return
        }

        Remove-Item -LiteralPath $launcherPath, $cmdLauncherPath -Force -ErrorAction SilentlyContinue

        Write-Section 'Install'
        Write-SuccessLine 'Removed TOI Git launchers.'
        Write-InfoLine "Target directory: $resolvedTargetDir"
    }

    function Set-UserBinInstall {
        $resolvedTargetDir = Get-UserBinDirectory
        $launcherPath = Join-Path $resolvedTargetDir 'toi.ps1'
        $cmdLauncherPath = Join-Path $resolvedTargetDir 'toi.cmd'
        $ps1Wrapper = @(
            'param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)'
            ''
            "& '$toiPath' @Args"
            ''
        ) -join [Environment]::NewLine
        $cmdWrapper = @(
            '@echo off'
            'setlocal'
            'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0toi.ps1" %*'
            ''
        ) -join [Environment]::NewLine

        if ($dryRun) {
            Write-Section 'Install'
            Write-InfoLine 'Mode: user-bin'
            Write-InfoLine "Target directory: $resolvedTargetDir"
            Write-InfoLine "On PATH: $(Test-PathContainsDirectory -Directory $resolvedTargetDir)"
            Write-InfoLine 'Dry run: True'
            Write-InfoLine "PowerShell wrapper: $launcherPath"
            Write-InfoLine "cmd launcher: $cmdLauncherPath"
            return
        }

        if (-not (Test-Path -LiteralPath $resolvedTargetDir)) {
            New-Item -ItemType Directory -Path $resolvedTargetDir -Force | Out-Null
        }

        Set-Content -LiteralPath $launcherPath -Value $ps1Wrapper
        Set-Content -LiteralPath $cmdLauncherPath -Value $cmdWrapper

        Write-Section 'Install'
        Write-SuccessLine 'Installed TOI Git launchers.'
        Write-InfoLine "PowerShell wrapper: $launcherPath"
        Write-InfoLine "cmd launcher: $cmdLauncherPath"
        if (Test-PathContainsDirectory -Directory $resolvedTargetDir) {
            Write-InfoLine 'The target directory is already on PATH.'
        }
        else {
            Write-WarningLine 'The target directory is not on PATH yet.'
            Write-InfoLine "Add it to PATH to use bare commands like: toi status"
        }
    }

    function Remove-ModuleInstall {
        $moduleDirectory = Get-ModuleInstallDirectory

        if ($dryRun) {
            Write-Section 'Install'
            Write-InfoLine 'Action: uninstall'
            Write-InfoLine 'Mode: module'
            Write-InfoLine "Module directory: $moduleDirectory"
            Write-InfoLine 'Dry run: True'
            return
        }

        Remove-Item -LiteralPath $moduleDirectory -Recurse -Force -ErrorAction SilentlyContinue

        Write-Section 'Install'
        Write-SuccessLine 'Removed TOI Git module files.'
        Write-InfoLine "Module directory: $moduleDirectory"
    }

    function Set-ModuleInstall {
        $moduleRoot = Get-UserModuleRoot
        $moduleDirectory = Get-ModuleInstallDirectory
        $managedItems = @(Get-ManagedModuleItems)

        if ($dryRun) {
            Write-Section 'Install'
            Write-InfoLine 'Mode: module'
            Write-InfoLine "Module root: $moduleRoot"
            Write-InfoLine "Module directory: $moduleDirectory"
            Write-InfoLine "On PSModulePath: $(Test-ModulePathContainsDirectory -Directory $moduleRoot)"
            Write-InfoLine "Module version: $moduleVersion"
            Write-InfoLine 'Dry run: True'
            $managedItems | ForEach-Object { Write-InfoLine "Bundle item: $_" }
            return
        }

        if (-not (Test-Path -LiteralPath $moduleDirectory)) {
            New-Item -ItemType Directory -Path $moduleDirectory -Force | Out-Null
        }

        foreach ($item in $managedItems) {
            $sourcePath = Join-Path $repoRoot $item
            $destinationPath = Join-Path $moduleDirectory $item

            if (Test-Path -LiteralPath $destinationPath) {
                Remove-Item -LiteralPath $destinationPath -Recurse -Force
            }

            Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Recurse
        }

        Write-Section 'Install'
        Write-SuccessLine 'Installed TOI Git as a PowerShell module.'
        Write-InfoLine "Module directory: $moduleDirectory"
        Write-InfoLine 'Open a new shell or run: Import-Module TOIGit -Force'
        Write-InfoLine 'Then you can use: toi status'
    }

    function Show-InstallStatus {
        $resolvedProfilePath = Get-ResolvedProfilePath
        $userBinDirectory = Get-UserBinDirectory
        $moduleRoot = Get-UserModuleRoot
        $moduleDirectory = Get-ModuleInstallDirectory

        Write-Section 'Install Status'
        Write-KeyValue 'Profile' (Test-ProfileInstalled)
        Write-KeyValue 'Profile Path' $resolvedProfilePath
        Write-KeyValue 'User Bin' (Test-UserBinInstalled)
        Write-KeyValue 'User Bin Path' $userBinDirectory
        Write-KeyValue 'On PATH' (Test-PathContainsDirectory -Directory $userBinDirectory)
        Write-KeyValue 'Module' (Test-ModuleInstalled)
        Write-KeyValue 'Module Root' $moduleRoot
        Write-KeyValue 'Module Path' $moduleDirectory
        Write-KeyValue 'On PSModulePath' (Test-ModulePathContainsDirectory -Directory $moduleRoot)
        Write-KeyValue 'Module Version' $moduleVersion
    }

    if ($action -eq 'status') {
        Show-InstallStatus
        return
    }

    if ($action -eq 'uninstall') {
        switch ($mode) {
            'profile' { Remove-ProfileInstall; return }
            'user-bin' { Remove-UserBinInstall; return }
            'module' { Remove-ModuleInstall; return }
            default { throw "Unsupported uninstall mode '$mode'." }
        }
    }

    switch ($mode) {
        'profile' { Set-ProfileInstall }
        'user-bin' { Set-UserBinInstall }
        'module' { Set-ModuleInstall }
        default { throw "Unsupported install mode '$mode'." }
    }
}
