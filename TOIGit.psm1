$script:ToiModuleRoot = Split-Path -Parent $PSCommandPath
$script:ToiEntryPoint = Join-Path $script:ToiModuleRoot 'toi.ps1'

& $script:ToiEntryPoint completion register *> $null

function Invoke-Toi {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    if (-not (Test-Path -LiteralPath $script:ToiEntryPoint)) {
        throw "Missing TOI entrypoint: $script:ToiEntryPoint"
    }

    & $script:ToiEntryPoint @Arguments
}

function Get-ToiVersion {
    [CmdletBinding()]
    param()

    if (-not (Test-Path -LiteralPath $script:ToiEntryPoint)) {
        throw "Missing TOI entrypoint: $script:ToiEntryPoint"
    }

    & $script:ToiEntryPoint version -Json | ConvertFrom-Json
}

Set-Alias -Name toi -Value Invoke-Toi

Export-ModuleMember -Function Invoke-Toi, Get-ToiVersion -Alias toi
