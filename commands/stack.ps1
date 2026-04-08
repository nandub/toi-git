function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not (Test-StackedBranchesEnabled)) {
        throw 'Stacked branches are disabled in toi.json.'
    }

    $action = if ($Arguments.Count -gt 0) { $Arguments[0].ToLowerInvariant() } else { 'list' }

    switch ($action) {
        'new' {
            if ($Arguments.Count -lt 2) {
                throw 'Usage: .\toi.ps1 stack new <name> [type]'
            }

            $name = $Arguments[1]
            $type = if ($Arguments.Count -ge 3) { $Arguments[2].ToLowerInvariant() } else { 'feature' }
            $allowedTypes = Get-AllowedBranchTypes

            if ($allowedTypes -notcontains $type) {
                throw "Unknown branch type '$type'. Allowed types: $($allowedTypes -join ', ')"
            }

            $branchName = New-BranchName -Type $type -Name $name
            if (Test-BranchExists -BranchName $branchName) {
                throw "Branch '$branchName' already exists."
            }

            $baseRef = Get-BranchBaseRef -BranchType $type -Stack

            Write-Section 'Stack New'
            Write-InfoLine "Branch: $branchName"
            Write-InfoLine "Parent: $baseRef"

            $result = Invoke-Git -GitArguments @('checkout', '-b', $branchName, $baseRef)
            $result.Output | ForEach-Object { Write-Host $_ }
        }
        'restack' {
            $defaultBranch = Get-DefaultBranchName
            $currentBranch = Get-CurrentBranchName

            Write-Section 'Stack Restack'
            Write-InfoLine "Branch: $currentBranch"
            Write-InfoLine "Onto: $defaultBranch"

            if (-not (Test-WorkingTreeClean)) {
                throw 'Working tree must be clean before restacking.'
            }

            $result = Invoke-Git -GitArguments @('rebase', $defaultBranch)
            $result.Output | ForEach-Object { Write-Host $_ }
        }
        'list' {
            $defaultBranch = Get-DefaultBranchName
            $result = Invoke-Git -GitArguments @('for-each-ref', '--format=%(refname:short)', 'refs/heads')
            $branches = @($result.Output | Where-Object { $_ -and $_ -ne $defaultBranch })

            Write-Section 'Stack Candidates'
            if ($branches.Count -eq 0) {
                Write-InfoLine 'No non-default local branches found.'
                return
            }

            $branches | ForEach-Object { Write-Host $_ }
        }
        default {
            throw 'Usage: .\toi.ps1 stack <new|restack|list> [args]'
        }
    }
}
