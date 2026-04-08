function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $branch = Get-CurrentBranchName
    $action = if ($Arguments.Count -gt 0) { $Arguments[0].ToLowerInvariant() } else { 'show' }

    switch ($action) {
        'show' {
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
            if ($Arguments.Count -lt 2) {
                throw 'Usage: .\\toi.ps1 note set <text>'
            }

            $note = (($Arguments | Select-Object -Skip 1) -join ' ').Trim()
            if (-not $note) {
                throw 'Branch note cannot be empty.'
            }

            Set-ToiBranchNote -BranchName $branch -Note $note
            Write-Section 'Branch Note'
            Write-InfoLine "Saved note for $branch"
            Write-InfoLine $note
        }
        'clear' {
            Remove-ToiBranchNote -BranchName $branch
            Write-Section 'Branch Note'
            Write-InfoLine "Cleared note for $branch"
        }
        default {
            throw 'Usage: .\\toi.ps1 note <show|set|clear> [text]'
        }
    }
}

