function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    if (-not (Test-ReleaseBranchesEnabled)) {
        throw 'Release branches are disabled in toi.json.'
    }

    if ($Arguments.Count -lt 2 -or $Arguments[0].ToLowerInvariant() -ne 'start') {
        throw 'Usage: .\toi.ps1 release start <version>'
    }

    $version = $Arguments[1]
    $branchName = New-BranchName -Type 'release' -Name $version
    $baseRef = Get-BranchBaseRef -BranchType 'release'

    if (Test-BranchExists -BranchName $branchName) {
        throw "Branch '$branchName' already exists."
    }

    Write-Section 'Release Start'
    Write-InfoLine "Branch: $branchName"
    Write-InfoLine "Base: $baseRef"

    $result = Invoke-Git -GitArguments @('checkout', '-b', $branchName, $baseRef)
    $result.Output | ForEach-Object { Write-Host $_ }
}
