function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    Write-Section 'Fetch'
    $fetchResult = Invoke-Git -GitArguments @('fetch', '--all', '--prune')

    if ($fetchResult.Output.Count -gt 0) {
        $fetchResult.Output | ForEach-Object { Write-Host $_ }
    }
    else {
        Write-SuccessLine 'Fetch completed.'
    }

    $branch = Get-CurrentBranchName
    $statusResult = Invoke-Git -GitArguments @('status', '--short', '--branch')

    Write-Section 'Tracking'
    Write-Host "Branch: $branch"
    $statusResult.Output | Select-Object -First 1 | ForEach-Object { Write-Host $_ }
}
