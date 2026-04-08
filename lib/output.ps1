function Write-Section {
    param([string]$Text)

    Write-Host ''
    Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Write-KeyValue {
    param(
        [string]$Key,
        [string]$Value
    )

    Write-Host ($Key.PadRight(18) + $Value)
}

function Write-StatusBadge {
    param(
        [string]$Label,
        [ValidateSet('good', 'warn', 'bad', 'neutral')]
        [string]$Tone = 'neutral'
    )

    $color = switch ($Tone) {
        'good' { 'Green' }
        'warn' { 'Yellow' }
        'bad' { 'Red' }
        default { 'Gray' }
    }

    Write-Host "[$Label]" -ForegroundColor $color -NoNewline
}

function Write-BulletLine {
    param([string]$Text)

    Write-Host "- $Text"
}

function Write-InfoLine {
    param([string]$Text)

    Write-Host $Text -ForegroundColor Gray
}

function Write-SuccessLine {
    param([string]$Text)

    Write-Host $Text -ForegroundColor Green
}

function Write-WarningLine {
    param([string]$Text)

    Write-Host $Text -ForegroundColor Yellow
}

function Write-ErrorLine {
    param([string]$Text)

    Write-Host $Text -ForegroundColor Red
}
