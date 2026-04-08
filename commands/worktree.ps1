function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $action = if ($Arguments.Count -gt 0) { $Arguments[0].ToLowerInvariant() } else { 'list' }

    switch ($action) {
        'list' {
            $result = Invoke-Git -GitArguments @('worktree', 'list')
            Write-Section 'Worktrees'
            $result.Output | ForEach-Object { Write-Host $_ }
        }
        'add' {
            if ($Arguments.Count -lt 2) {
                throw 'Usage: .\\toi.ps1 worktree add <path> [branch]'
            }

            $path = $Arguments[1]
            $branch = if ($Arguments.Count -ge 3) { $Arguments[2] } else { $null }

            Write-Section 'Worktree Add'
            Write-InfoLine "Path: $path"
            if ($branch) {
                Write-InfoLine "Branch: $branch"
                $result = Invoke-Git -GitArguments @('worktree', 'add', $path, $branch)
            }
            else {
                $result = Invoke-Git -GitArguments @('worktree', 'add', $path)
            }

            $result.Output | ForEach-Object { Write-Host $_ }
        }
        default {
            throw 'Usage: .\\toi.ps1 worktree <list|add> [args]'
        }
    }
}

