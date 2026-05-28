# ==================================================================================================
# BRAVO Logging
# ==================================================================================================

function Get-BravoConsoleOption {
    param(
        [string]$Name,
        [object]$Default = $null
    )

    if (Get-Command Get-BravoConfigValue -ErrorAction SilentlyContinue) {
        return Get-BravoConfigValue -Name $Name -Default $Default
    }

    return $Default
}

function Get-BravoConsoleWidth {
    $width = [int](Get-BravoConsoleOption -Name "ConsoleWidth" -Default 80)

    if ($width -lt 60) { return 60 }
    if ($width -gt 140) { return 140 }

    return $width
}

function Get-BravoConsoleIconsMode {
    return [string](Get-BravoConsoleOption -Name "ConsoleIcons" -Default "emoji")
}

function Get-BravoConsoleStyle {
    return [string](Get-BravoConsoleOption -Name "ConsoleStyle" -Default "classic")
}

function Get-BravoConsoleIcon {
    param(
        [string]$Name
    )

    $mode = Get-BravoConsoleIconsMode

    if ($mode -eq "off") {
        return ""
    }

    $emoji = @{
        Search  = "🔍"
        Stop    = "⚡"
        File    = "📄"
        Restore = "🔄"
        Logs    = "📊"
        Start   = "🚀"
        Cleanup = "🧹"
        Success = "✔"
        Warning = "!"
        Error   = "✖"
        Info    = "•"
    }

    $ascii = @{
        Search  = "?"
        Stop    = "!"
        File    = "#"
        Restore = "*"
        Logs    = "%"
        Start   = ">"
        Cleanup = "-"
        Success = "OK"
        Warning = "!"
        Error   = "X"
        Info    = "*"
    }

    if ($mode -eq "ascii") {
        if ($ascii.ContainsKey($Name)) { return $ascii[$Name] }
        return "*"
    }

    if ($emoji.ContainsKey($Name)) { return $emoji[$Name] }
    return "•"
}

function Write-BravoConsoleRaw {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    switch ($Level) {
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        "ERROR"   { Write-Host $Message -ForegroundColor Red }
        "WARNING" { Write-Host $Message -ForegroundColor Yellow }
        "DEBUG"   { Write-Host $Message -ForegroundColor Gray }
        default   { Write-Host $Message -ForegroundColor White }
    }
}

function Write-BravoConsoleBox {
    param(
        [string]$Title,
        [string[]]$Lines = @()
    )

    $width = Get-BravoConsoleWidth
    $innerWidth = $width - 2

    $safeTitle = " $Title "
    $topFill = [Math]::Max(0, $innerWidth - $safeTitle.Length)
    $top = "┌" + "───[" + $safeTitle + "]" + ("─" * [Math]::Max(0, $topFill - 4)) + "┐"
    $bottom = "└" + ("─" * $innerWidth) + "┘"

    Write-BravoConsoleRaw -Message $top -Level "INFO"

    foreach ($line in $Lines) {
        $content = "  $line"
        if ($content.Length -gt $innerWidth) {
            $content = $content.Substring(0, $innerWidth)
        }

        $padding = " " * ($innerWidth - $content.Length)
        Write-BravoConsoleRaw -Message "│$content$padding│" -Level "INFO"
    }

    Write-BravoConsoleRaw -Message $bottom -Level "INFO"
}

function Write-BravoConsoleSection {
    param(
        [string]$Title,
        [string]$Icon = "Info"
    )

    $iconText = Get-BravoConsoleIcon -Name $Icon

    if ([string]::IsNullOrWhiteSpace($iconText)) {
        Write-BravoConsoleRaw -Message "[$Title]..." -Level "INFO"
    }
    else {
        Write-BravoConsoleRaw -Message "[$iconText] $Title..." -Level "INFO"
    }
}

function Format-BravoConsoleStatusLine {
    param(
        [string]$Name,
        [string]$Status,
        [int]$NameWidth = -1,
        [int]$StatusWidth = -1
    )

    if ($NameWidth -lt 1) {
        $NameWidth = [int](Get-BravoConsoleOption -Name "ConsoleLabelWidth" -Default 12)
    }

    if ($StatusWidth -lt 1) {
        $StatusWidth = [int](Get-BravoConsoleOption -Name "ConsoleStatusWidth" -Default 12)
    }

    $width = Get-BravoConsoleWidth
    $prefix = "    ↳ "
    $left = $Name.PadRight($NameWidth)
    $statusText = "[ " + $Status.PadRight($StatusWidth) + " ]"
    $dotsCount = $width - $prefix.Length - $left.Length - $statusText.Length - 1

    if ($dotsCount -lt 3) {
        $dotsCount = 3
    }

    return $prefix + $left + ("." * $dotsCount) + " " + $statusText
}

function Write-BravoConsoleStatus {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Level = "SUCCESS"
    )

    Write-BravoConsoleRaw -Message (Format-BravoConsoleStatusLine -Name $Name -Status $Status) -Level $Level
}

function Write-BravoConsoleStep {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    Write-BravoConsoleRaw -Message "    ↳ $Message" -Level $Level
}

function Write-BravoConsoleFinalLine {
    param(
        [string]$Status,
        [string]$Duration,
        [string]$ObjectName
    )

    $width = Get-BravoConsoleWidth
    $line = "─" * $width
    $icon = Get-BravoConsoleIcon -Name "Success"

    Write-BravoConsoleRaw -Message $line -Level "INFO"
    Write-BravoConsoleRaw -Message "[$icon] СТАТУС: $Status | ЧАС: $Duration | УСТАНОВА: $ObjectName" -Level "SUCCESS"
    Write-BravoConsoleRaw -Message $line -Level "INFO"
}

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [int]$SeparatorLength = 100,
        [switch]$NoTimestamp
    )
    
    # Перевірка рівня логування
    $logLevels = @{"DEBUG"=0; "INFO"=1; "WARNING"=2; "ERROR"=3; "SUCCESS"=4}
    
    # Отримуємо поточний рівень логування з глобальної змінної
    $currentLogLevel = if ($global:LogLevel -and $logLevels.ContainsKey($global:LogLevel)) { 
        $logLevels[$global:LogLevel] 
    } else { 
        1 # Значення за замовчуванням - INFO
    }
    
    $messageLevel = if ($logLevels.ContainsKey($Level)) { 
        $logLevels[$Level] 
    } else { 
        1 # Значення за замовчуванням - INFO
    }
    
    # Пропускаємо повідомлення нижчого рівня
    if ($messageLevel -lt $currentLogLevel) {
        return
    }
    
    # Обробка спеціальних повідомлень-роздільників
    if ($Message -eq "=" -or $Message -eq "===") {
        $separator = "=" * $SeparatorLength
        Write-Host $separator -ForegroundColor White
        try {
            if (-not (Test-Path $LOG_DIR)) {
                New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
            }
            $separator | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
        } catch {
            Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }
    
    # Обробка заголовків
    if ($Message -match "^=== .* ===$") {
        Write-Host $Message -ForegroundColor Yellow
        try {
            if (-not (Test-Path $LOG_DIR)) {
                New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
            }
            $Message | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
        } catch {
            Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
        }
        return
    }
    
    # Звичайні повідомлення
if ($NoTimestamp) {
    $logEntry = $Message
    $consoleEntry = $Message
} else {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    # У файл пишемо повний запис з timestamp і level
    $logEntry = "[$timestamp] [$Level] $Message"

    # У консоль пишемо тільки текст повідомлення без timestamp/level
    $consoleEntry = $Message
}

switch ($Level) {
    "SUCCESS" { Write-Host $consoleEntry -ForegroundColor Green }
    "ERROR"   { Write-Host $consoleEntry -ForegroundColor Red }
    "WARNING" { Write-Host $consoleEntry -ForegroundColor Yellow }
    "DEBUG"   { Write-Host $consoleEntry -ForegroundColor Gray }
    default   { Write-Host $consoleEntry -ForegroundColor White }
}
    
    try {
        if (-not (Test-Path $LOG_DIR)) {
            New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
        }
        $logEntry | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
    } catch {
        Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
    }
}
