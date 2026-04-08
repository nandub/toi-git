function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $statusLines = Get-StatusLines
    $branchLine = $statusLines | Select-Object -First 1
    $fileLines = $statusLines | Select-Object -Skip 1

    Write-Section 'Status'
    Write-Host $branchLine

    if (-not $fileLines -or $fileLines.Count -eq 0) {
        Write-SuccessLine 'Working tree is clean.'
        return
    }

    $staged = @()
    $unstaged = @()
    $untracked = @()

    foreach ($line in $fileLines) {
        if ($line.Length -lt 3) {
            continue
        }

        $indexState = $line.Substring(0, 1)
        $workTreeState = $line.Substring(1, 1)
        $path = $line.Substring(3)

        if ($indexState -ne ' ' -and $indexState -ne '?') {
            $staged += $path
        }

        if ($workTreeState -ne ' ' -and -not ($indexState -eq '?' -and $workTreeState -eq '?')) {
            $unstaged += $path
        }

        if ($indexState -eq '?' -and $workTreeState -eq '?') {
            $untracked += $path
        }
    }

    if ($staged.Count -gt 0) {
        Write-Section 'Staged'
        $staged | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
    }

    if ($unstaged.Count -gt 0) {
        Write-Section 'Unstaged'
        $unstaged | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
    }

    if ($untracked.Count -gt 0) {
        Write-Section 'Untracked'
        $untracked | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
    }
}
