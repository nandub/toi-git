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
                throw 'Usage: toi stack new <name> [type]'
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
            Set-ToiStackParent -BranchName $branchName -ParentBranch $baseRef
        }
        'restack' {
            $defaultBranch = Get-DefaultBranchName
            $currentBranch = Get-CurrentBranchName
            $parentBranch = Get-ToiStackParent -BranchName $currentBranch
            $rebaseTarget = if ($parentBranch) { $parentBranch } else { $defaultBranch }

            Write-Section 'Stack Restack'
            Write-InfoLine "Branch: $currentBranch"
            Write-InfoLine "Onto: $rebaseTarget"

            if (-not (Test-WorkingTreeClean)) {
                throw 'Working tree must be clean before restacking.'
            }

            $result = Invoke-Git -GitArguments @('rebase', $rebaseTarget)
            $result.Output | ForEach-Object { Write-Host $_ }
        }
        'list' {
            $defaultBranch = Get-DefaultBranchName
            $stackBranches = Get-ToiStackBranches
            $result = Invoke-Git -GitArguments @('for-each-ref', '--format=%(refname:short)', 'refs/heads')
            $branches = @($result.Output | Where-Object { $_ -and $_ -ne $defaultBranch })

            Write-Section 'Stack Candidates'
            if ($branches.Count -eq 0) {
                Write-InfoLine 'No non-default local branches found.'
                return
            }

            foreach ($branch in $branches) {
                $stackEntry = $stackBranches | Where-Object { $_.Branch -eq $branch } | Select-Object -First 1
                if ($stackEntry) {
                    Write-Host "$branch <- $($stackEntry.Parent)"
                }
                else {
                    Write-Host $branch
                }
            }
        }
        'parent' {
            $currentBranch = Get-CurrentBranchName
            $parentBranch = Get-ToiStackParent -BranchName $currentBranch

            Write-Section 'Stack Parent'
            if ($parentBranch) {
                Write-InfoLine "$currentBranch <- $parentBranch"
            }
            else {
                Write-InfoLine 'No explicit stack parent recorded for the current branch.'
            }
        }
        default {
            throw 'Usage: toi stack <new|restack|list|parent> [args]'
        }
    }
}

