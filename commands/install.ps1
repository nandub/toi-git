function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $mode = 'profile'
    $dryRun = $false
    $targetDir = $null
    $profilePath = $null

    for ($index = 0; $index -lt $Arguments.Count; $index++) {
        $argument = $Arguments[$index]

        switch -Regex ($argument) {
            '^(profile|user-bin)$' {
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

    function Set-ProfileInstall {
        $resolvedProfilePath = if ($profilePath) { $profilePath } else { $PROFILE.CurrentUserCurrentHost }
        $snippet = Get-InstallSnippet
        $existingContent = ''

        if (Test-Path -LiteralPath $resolvedProfilePath) {
            $existingContent = Get-Content -LiteralPath $resolvedProfilePath -Raw
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
        Write-InfoLine 'Open a new shell or run: . $PROFILE'
        Write-InfoLine 'Then you can use: toi status'
    }

    function Set-UserBinInstall {
        $resolvedTargetDir = if ($targetDir) { $targetDir } else { Join-Path $HOME 'bin' }
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

    switch ($mode) {
        'profile' {
            Set-ProfileInstall
        }
        'user-bin' {
            Set-UserBinInstall
        }
        default {
            throw "Unsupported install mode '$mode'."
        }
    }
}
