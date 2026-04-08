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
    $upstreamRef = Get-UpstreamRef
    $syncStrategy = Get-SyncStrategy

    Write-Section 'Tracking'
    Write-Host "Branch: $branch"

    if ($upstreamRef) {
        Write-Host "Upstream: $upstreamRef"

        if (Test-WorkingTreeClean) {
            if ($syncStrategy -eq 'rebase') {
                $updateResult = Invoke-Git -GitArguments @('pull', '--rebase', '--autostash')
            }
            else {
                $updateResult = Invoke-Git -GitArguments @('pull', '--ff-only')
            }

            Write-Section 'Update'
            $updateResult.Output | ForEach-Object { Write-Host $_ }
        }
        else {
            Write-WarningLine 'Working tree is not clean. Fetch completed, but branch update was skipped.'
        }
    }
    else {
        Write-InfoLine 'No upstream configured for the current branch.'
    }
}
