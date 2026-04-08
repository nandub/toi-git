function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if ($Arguments.Count -lt 2 -or $Arguments[0].ToLowerInvariant() -ne 'start') {
        throw 'Usage: toi hotfix start <name>'
    }

    $name = ($Arguments | Select-Object -Skip 1) -join ' '
    $branchName = New-BranchName -Type 'hotfix' -Name $name
    $baseRef = Get-BranchBaseRef -BranchType 'hotfix'

    if (Test-BranchExists -BranchName $branchName) {
        throw "Branch '$branchName' already exists."
    }

    Write-Section 'Hotfix Start'
    Write-InfoLine "Branch: $branchName"
    Write-InfoLine "Base: $baseRef"

    $result = Invoke-Git -GitArguments @('checkout', '-b', $branchName, $baseRef)
    $result.Output | ForEach-Object { Write-Host $_ }
}

