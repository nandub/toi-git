function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $apply = $Arguments -contains '-Apply'
    $currentBranch = Get-CurrentBranchName
    $protectedBranches = Get-ProtectedBranches

    if (-not (Test-HasCommits)) {
        Write-Section 'Merged Branches'
        Write-InfoLine 'No commits yet. Branch cleanup is unavailable until the repository has history.'
        return
    }

    $mergedResult = Invoke-Git -GitArguments @('branch', '--merged')
    $branches = foreach ($line in $mergedResult.Output) {
        $name = $line.Replace('*', '').Trim()
        if (-not $name) {
            continue
        }

        if ($name -eq $currentBranch) {
            continue
        }

        if ($protectedBranches -contains $name) {
            continue
        }

        $name
    }

    Write-Section 'Merged Branches'

    if (-not $branches -or $branches.Count -eq 0) {
        Write-SuccessLine 'No merged local branches to clean.'
        return
    }

    $branches = $branches | Sort-Object -Unique
    $branches | ForEach-Object { Write-Host $_ }

    if (-not $apply) {
        Write-Host ''
        Write-InfoLine 'Preview only. Re-run with -Apply to delete these branches.'
        return
    }

    Write-Section 'Deleting'
    foreach ($branch in $branches) {
        $deleteResult = Invoke-Git -GitArguments @('branch', '-d', $branch)
        $deleteResult.Output | ForEach-Object { Write-Host $_ }
    }
}
