function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not (Test-ReleaseBranchesEnabled)) {
        throw 'Release branches are disabled in toi.json.'
    }

    if ($Arguments.Count -lt 2) {
        throw 'Usage: .\toi.ps1 release <start|notes|tag> <version>'
    }

    $action = $Arguments[0].ToLowerInvariant()
    $version = $Arguments[1]

    if (-not (Test-ValidReleaseVersion -Version $version)) {
        throw "Version '$version' does not match the configured releaseVersionPattern."
    }

    $branchName = New-BranchName -Type 'release' -Name $version
    $tagName = Get-ReleaseTagName -Version $version
    $notesFile = Get-ReleaseNotesFile
    $latestTag = Get-LatestReleaseTag

    switch ($action) {
        'start' {
            $baseRef = Get-BranchBaseRef -BranchType 'release'

            if (Test-BranchExists -BranchName $branchName) {
                throw "Branch '$branchName' already exists."
            }

            Write-Section 'Release Start'
            Write-InfoLine "Version: $version"
            Write-InfoLine "Branch: $branchName"
            Write-InfoLine "Base: $baseRef"
            if ($latestTag) {
                Write-InfoLine "Previous tag: $latestTag"
            }

            $result = Invoke-Git -GitArguments @('checkout', '-b', $branchName, $baseRef)
            $result.Output | ForEach-Object { Write-Host $_ }
        }
        'notes' {
            $content = New-ReleaseNotesContent -Version $version -SinceRef $latestTag
            Set-Content -LiteralPath $notesFile -Value $content

            Write-Section 'Release Notes'
            Write-InfoLine "Version: $version"
            Write-InfoLine "File: $notesFile"
            if ($latestTag) {
                Write-InfoLine "Since: $latestTag"
            }
            else {
                Write-InfoLine 'Since: repository start'
            }
        }
        'tag' {
            if (-not (Test-WorkingTreeClean)) {
                throw 'Working tree must be clean before creating a release tag.'
            }

            if (Test-TagExists -TagName $tagName) {
                throw "Tag '$tagName' already exists."
            }

            $message = "Release $version"
            $result = Invoke-Git -GitArguments @('tag', '-a', $tagName, '-m', $message)

            Write-Section 'Release Tag'
            Write-InfoLine "Tag: $tagName"
            Write-InfoLine "Message: $message"
            $result.Output | ForEach-Object { Write-Host $_ }
        }
        default {
            throw 'Usage: .\toi.ps1 release <start|notes|tag> <version>'
        }
    }
}
