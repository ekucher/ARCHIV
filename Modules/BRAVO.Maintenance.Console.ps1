# ==============================================================================
# BRAVO.Maintenance.Console.ps1
# Автоматично винесені функції з BRAVO_MAINTENANCE.ps1
# ==============================================================================

function Write-MaintenanceLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [int]$SeparatorLength = 100,
        [switch]$NoTimestamp,
        [switch]$NoPrefix
    )

    $isDebugMode = ($global:LogLevel -eq "DEBUG")
    if ($Level -eq "DEBUG" -and -not $isDebugMode) {
        return
    }

    $separator = "─" * 92

    if ($Message -eq "=" -or $Message -eq "===") {
        Write-Host $separator -ForegroundColor DarkGray
        Write-BravoLogFileLine -Line $separator
        return
    }

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return
    }

    if ($Message -match "^===\s*(.+?)\s*===$") {
        $header = $Matches[1].Trim()
        Write-Host $separator -ForegroundColor DarkGray
        Write-Host $header -ForegroundColor Cyan
        Write-BravoLogFileLine -Line $separator
        Write-BravoLogFileLine -Line $header
        return
    }

    $consoleMessage = $Message
    $fileMessage = $Message

    if ($Message -match "^✓") {
        Write-Host $consoleMessage -ForegroundColor Green
    } elseif ($Message -match "^✕|ПОМИЛКА|ERROR") {
        Write-Host $consoleMessage -ForegroundColor Red
    } elseif ($Message -match "^!") {
        Write-Host $consoleMessage -ForegroundColor Yellow
    } elseif ($Level -eq "DEBUG") {
        # DEBUG пишемо тільки в лог, щоб консоль залишалась компактною.
    } else {
        Write-Host $consoleMessage -ForegroundColor White
    }

    Write-BravoLogFileLine -Line $fileMessage
}
function Write-Action {
    param(
        [string]$Action,
        [string]$Result,
        [switch]$IsError
    )

    $cleanAction = ($Action -replace '\.{2,}$', '').Trim()
    $cleanResult = $Result -replace '✓', '✓'
    $cleanResult = $cleanResult -replace '✕', '✕'
    $cleanResult = $cleanResult.Trim()
    $paddedAction = $cleanAction.PadRight(38)

    if ($IsError -or $cleanResult -match '✕|ПОМИЛКА|Не вдалося|не знайдено') {
        $line = " ✕ $paddedAction $cleanResult"
        Write-Host $line -ForegroundColor Red
    } elseif ($cleanResult -match '^✓|Успішно|Вже|Немає|Оброблено|запущено|зупинено') {
        $line = " ✓ $paddedAction $cleanResult"
        Write-Host $line -ForegroundColor Green
    } else {
        $line = " • $paddedAction $cleanResult"
        Write-Host $line -ForegroundColor Gray
    }
    
    Write-BravoLogFileLine -Line $line
}

function Write-ActionHeader {
    param([string]$Header)

    $separator = "─" * 92
    Write-Host $separator -ForegroundColor DarkGray
    Write-Host $Header -ForegroundColor Cyan
    Write-BravoLogFileLine -Line $separator
    Write-BravoLogFileLine -Line $Header
}
function Write-Success {
    param([string]$Message)
    Write-MaintenanceLog -Message "✓ $Message" -Level "INFO"
}

function Write-ErrorLog {
    param([string]$Message)
    $global:criticalErrorOccurred = $true
    Write-MaintenanceLog -Message "✕ $Message" -Level "ERROR"
}

function Format-Duration {
    param([TimeSpan]$duration)
    if ($duration.TotalHours -ge 1) {
        $hours = [math]::Floor($duration.TotalHours)
        $minutes = $duration.Minutes
        $seconds = $duration.Seconds
        return "$hours год. ${minutes}хв. ${seconds}сек."
    } elseif ($duration.TotalMinutes -ge 1) {
        return "$($duration.Minutes)хв. $($duration.Seconds)сек."
    } else {
        return "$($duration.Seconds) сек."
    }
}

function Format-CommandOutput {
    param([string]$Output)
    if ($global:LogLevel -eq "DEBUG" -and -not [string]::IsNullOrWhiteSpace($Output)) {
        return "`n" + ($Output -replace "`r?`n", "`n    ") + "`n"
    }
    return ""
}

function Format-FileSize {
    param([long]$size)
    switch ($size) {
        { $_ -ge 1GB } { return "{0:N2} ГБ" -f ($size / 1GB) }
        { $_ -ge 1MB } { return "{0:N2} МБ" -f ($size / 1MB) }
        { $_ -ge 1KB } { return "{0:N2} КБ" -f ($size / 1KB) }
        default { return "$size байт" }
    }
}

