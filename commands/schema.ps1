function Invoke-ToiCommand {
    param([string[]]$Arguments)

    Assert-InGitRepository

    $json = $Arguments -contains '-Json'
    $snapshot = $Arguments -contains '-Snapshot'
    $writeSnapshot = $Arguments -contains '-WriteSnapshot'
    $checkSnapshot = $Arguments -contains '-CheckSnapshot'
    $bumpIndex = [Array]::IndexOf($Arguments, '-BumpVersion')
    $bumpKind = $null
    if ($bumpIndex -ge 0) {
        if ($bumpIndex + 1 -ge $Arguments.Count) {
            throw 'Expected one of: major, minor, patch after -BumpVersion.'
        }

        $bumpKind = $Arguments[$bumpIndex + 1].ToLowerInvariant()
        if (@('major', 'minor', 'patch') -notcontains $bumpKind) {
            throw "Invalid bump kind '$bumpKind'. Expected one of: major, minor, patch."
        }
    }

    if ($bumpKind) {
        $nextVersion = Get-ToiNextContractVersion -Bump $bumpKind
        $versionPath = Set-ToiContractVersion -Version $nextVersion
        $writeSnapshot = $true

        if (-not $json) {
            Write-Section 'Schema'
            Write-SuccessLine "Updated contract version: $nextVersion"
            Write-InfoLine "Version file: $versionPath"
        }
    }

    $schema = if ($snapshot) { Get-ToiSchemaSnapshotModel } else { Get-ToiSchemaModel }

    if ($checkSnapshot) {
        $check = Test-ToiContractSnapshotMatchesCurrent

        if ($json) {
            Write-Json $check
            return
        }

        Write-Section 'Schema'
        if ($check.matches) {
            Write-SuccessLine $check.reason
        }
        else {
            Write-WarningLine $check.reason
        }
        Write-InfoLine "Contract version: $($check.contract_version)"
        Write-InfoLine "Snapshot path: $($check.path)"
        if (-not $check.matches) {
            throw $check.reason
        }
        return
    }

    if ($writeSnapshot) {
        $snapshotPath = Get-ToiContractSnapshotPath
        $snapshotJson = Convert-ToiValueToCanonicalJson -Value (Get-ToiSchemaSnapshotModel)
        $snapshotDirectory = Split-Path -Parent $snapshotPath

        if (-not (Test-Path -LiteralPath $snapshotDirectory)) {
            New-Item -ItemType Directory -Path $snapshotDirectory -Force | Out-Null
        }

        Set-Content -LiteralPath $snapshotPath -Value $snapshotJson

        if ($json) {
            Write-Json ([PSCustomObject]@{
                updated = $true
                path = $snapshotPath
                contract_version = (Get-ToiContractVersion)
                bumped = [bool]$bumpKind
                bump = $bumpKind
            })
            return
        }

        if (-not $bumpKind) {
            Write-Section 'Schema'
        }
        Write-SuccessLine "Updated contract snapshot: $snapshotPath"
        Write-InfoLine "Contract version: $(Get-ToiContractVersion)"
        return
    }

    if ($json) {
        Write-Json $schema
        return
    }

    $markdown = Convert-ToiSchemaToMarkdown -Schema $schema
    Write-Host $markdown
}
