function Write-Section {
    param([string]$Text)

    Write-Host ''
    Write-Host "== $Text ==" -ForegroundColor Cyan
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
