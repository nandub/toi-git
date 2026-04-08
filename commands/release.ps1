function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $filteredArguments = @($Arguments | Where-Object { $_ -ne '-Json' })

    if (-not (Test-ReleaseBranchesEnabled)) {
        throw 'Release branches are disabled in toi.json.'
    }

    if ($filteredArguments.Count -lt 2) {
        throw 'Usage: toi release <start|notes|tag> <version>'
    }

    $action = $filteredArguments[0].ToLowerInvariant()
    $version = $filteredArguments[1]

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

            $result = Invoke-Git -GitArguments @('checkout', '-b', $branchName, $baseRef)
            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'start'
                    version = $version
                    branch = $branchName
                    base = $baseRef
                    previous_tag = $latestTag
                    output = @($result.Output)
                })
                return
            }

            Write-Section 'Release Start'
            Write-InfoLine "Version: $version"
            Write-InfoLine "Branch: $branchName"
            Write-InfoLine "Base: $baseRef"
            if ($latestTag) {
                Write-InfoLine "Previous tag: $latestTag"
            }
            $result.Output | ForEach-Object { Write-Host $_ }
        }
        'notes' {
            $content = New-ReleaseNotesContent -Version $version -SinceRef $latestTag
            Set-Content -LiteralPath $notesFile -Value $content

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'notes'
                    version = $version
                    file = $notesFile
                    since = $latestTag
                })
                return
            }

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

            if ($json) {
                Write-Json ([PSCustomObject]@{
                    action = 'tag'
                    version = $version
                    tag = $tagName
                    message = $message
                    output = @($result.Output)
                })
                return
            }

            Write-Section 'Release Tag'
            Write-InfoLine "Tag: $tagName"
            Write-InfoLine "Message: $message"
            $result.Output | ForEach-Object { Write-Host $_ }
        }
        default {
            throw 'Usage: toi release <start|notes|tag> <version>'
        }
    }
}

