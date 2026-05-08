function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $argumentList = @()
    if ($null -ne $Arguments) {
        $argumentList = @($Arguments)
    }
    $branch = Get-CurrentBranchName
    $action = if ($argumentList.Count -gt 0) { $argumentList[0].ToLowerInvariant() } else { 'show' }

    switch ($action) {
        'show' {
            if (-not $branch) {
                Write-Section 'Branch Note'
                Write-InfoLine 'No branch note is available while HEAD is detached.'
                return
            }

            $note = Get-ToiBranchNote -BranchName $branch
            Write-Section 'Branch Note'
            if ($note) {
                Write-InfoLine $note
            }
            else {
                Write-InfoLine 'No note recorded for the current branch.'
            }
        }
        'set' {
            if (-not $branch) {
                throw 'Branch notes require a named branch. Create or switch to a branch first.'
            }

            if ($argumentList.Count -lt 2) {
                throw 'Usage: .\\toi.ps1 note set <text>'
            }

            $note = (($argumentList | Select-Object -Skip 1) -join ' ').Trim()
            if (-not $note) {
                throw 'Branch note cannot be empty.'
            }

            Set-ToiBranchNote -BranchName $branch -Note $note
            Write-Section 'Branch Note'
            Write-InfoLine "Saved note for $branch"
            Write-InfoLine $note
        }
        'clear' {
            if (-not $branch) {
                throw 'Branch notes require a named branch. Create or switch to a branch first.'
            }

            Remove-ToiBranchNote -BranchName $branch
            Write-Section 'Branch Note'
            Write-InfoLine "Cleared note for $branch"
        }
        default {
            throw 'Usage: .\\toi.ps1 note <show|set|clear> [text]'
        }
    }
}

