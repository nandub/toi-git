$script:ToiModuleRoot = Split-Path -Parent $PSCommandPath
$script:ToiEntryPoint = Join-Path $script:ToiModuleRoot 'toi.ps1'

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

Set-Alias -Name toi -Value Invoke-Toi

Export-ModuleMember -Function Invoke-Toi -Alias toi
