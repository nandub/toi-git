function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if ($Arguments.Count -lt 2) {
        throw 'Usage: .\\toi.ps1 start <type> <name>'
    }

    $type = $Arguments[0].ToLowerInvariant()
    $name = ($Arguments | Select-Object -Skip 1) -join ' '
    $allowedTypes = Get-AllowedBranchTypes

    if ($allowedTypes -notcontains $type) {
        throw "Unknown branch type '$type'. Allowed types: $($allowedTypes -join ', ')"
    }

    $branchName = New-BranchName -Type $type -Name $name
    if (Test-BranchExists -BranchName $branchName) {
        throw "Branch '$branchName' already exists."
    }

    $baseRef = Get-BranchBaseRef -BranchType $type

    Write-Section 'Start'
    Write-InfoLine "Branch: $branchName"
    Write-InfoLine "Base: $baseRef"

    Invoke-Git -GitArguments @('fetch', '--all', '--prune') -AllowFailure | Out-Null
    $result = Invoke-Git -GitArguments @('checkout', '-b', $branchName, $baseRef)
    $result.Output | ForEach-Object { Write-Host $_ }
}

