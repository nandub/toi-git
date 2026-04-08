function Invoke-ToiCommand {
    param([string[]]$Arguments)

    $json = $Arguments -contains '-Json'
    $moduleManifestPath = Join-Path $PSScriptRoot '..\TOIGit.psd1'
    $moduleVersion = $null
    if (Test-Path -LiteralPath $moduleManifestPath) {
        $moduleVersion = (Test-ModuleManifest -Path $moduleManifestPath).Version.ToString()
    }

    $latestTag = $null
    $branch = $null
    $head = $null
    $aheadOfTag = $null

    try {
        Assert-InGitRepository
        $branch = Get-CurrentBranchName
        $head = (Invoke-Git -GitArguments @('rev-parse', '--short', 'HEAD')).Output | Select-Object -First 1
        $latestTag = Get-LatestReleaseTag

        if ($latestTag) {
            $aheadRaw = (Invoke-Git -GitArguments @('rev-list', '--count', "$latestTag..HEAD")).Output | Select-Object -First 1
            $aheadOfTag = [int]$aheadRaw
        }
    }
    catch {
    }

    $result = [PSCustomObject]@{
        module_version = $moduleVersion
        latest_tag = $latestTag
        branch = $branch
        head = $head
        commits_ahead_of_latest_tag = $aheadOfTag
    }

    if ($json) {
        Write-Json $result
        return
    }

    $latestTagDisplay = 'none'
    if ($latestTag) {
        $latestTagDisplay = $latestTag
    }

    Write-Section 'Version'
    Write-KeyValue 'Module' $moduleVersion
    Write-KeyValue 'Latest Tag' $latestTagDisplay
    if ($branch) {
        Write-KeyValue 'Branch' $branch
    }
    if ($head) {
        Write-KeyValue 'HEAD' $head
    }
    if ($aheadOfTag -ne $null) {
        Write-KeyValue 'Ahead Of Tag' $aheadOfTag
    }
}
