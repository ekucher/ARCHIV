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
    return [string](Get-BravoConsoleOption -Name "ConsoleIcons" -Default "ascii")
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
        Search  = "*"
        Stop    = "!"
        File    = "*"
        Restore = "*"
        Logs    = "*"
        Start   = "!"
        Cleanup = "*"
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

function Format-BravoConsoleBoxContent {
    param(
        [string]$Text,
        [int]$Width
    )

    $contentWidth = $Width - 4

    if ($contentWidth -lt 10) {
        $contentWidth = 10
    }

    $content = "  $Text"

    if ($content.Length -gt $contentWidth) {
        $content = $content.Substring(0, $contentWidth)
    }

    return "│" + $content.PadRight($contentWidth) + "  │"
}

function Write-BravoConsoleBox {
    param(
        [string]$Title,
        [string[]]$Lines = @()
    )

    $width = Get-BravoConsoleWidth

    if ($width -lt 60) {
        $width = 60
    }

    $innerWidth = $width - 2
    $top = "┌" + ("─" * $innerWidth) + "┐"
    $bottom = "└" + ("─" * $innerWidth) + "┘"

    Write-BravoConsoleRaw -Message $top -Level "INFO"
    Write-BravoConsoleRaw -Message (Format-BravoConsoleBoxContent -Text $Title -Width $width) -Level "INFO"

    foreach ($line in $Lines) {
        Write-BravoConsoleRaw -Message (Format-BravoConsoleBoxContent -Text $line -Width $width) -Level "INFO"
    }

    Write-BravoConsoleRaw -Message $bottom -Level "INFO"
}

function Get-BravoConsoleSectionSpacing {
    $spacing = [int](Get-BravoConsoleOption -Name "ConsoleSectionSpacing" -Default 1)

    if ($spacing -lt 0) {
        return 0
    }

    if ($spacing -gt 3) {
        return 3
    }

    return $spacing
}

function Write-BravoConsoleSectionSpacing {
    $spacing = Get-BravoConsoleSectionSpacing

    for ($i = 0; $i -lt $spacing; $i++) {
        Write-BravoConsoleRaw -Message "" -Level "INFO"
    }
}
function Write-BravoConsoleSection {
    param(
        [string]$Title,
        [string]$Icon = "Info"
    )

    Write-BravoConsoleSectionSpacing

    $iconText = Get-BravoConsoleIcon -Name $Icon

    if ([string]::IsNullOrWhiteSpace($iconText)) {
        Write-BravoConsoleRaw -Message "[$Title]..." -Level "INFO"
    }
    else {
        Write-BravoConsoleRaw -Message "[$iconText] $Title..." -Level "INFO"
    }
}

function Get-BravoConsoleBranchPrefix {
    $mode = Get-BravoConsoleIconsMode

    if ($mode -eq "emoji") {
        return "↳"
    }

    return "->"
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
    $prefix = "    $(Get-BravoConsoleBranchPrefix) "
    $left = $Name.PadRight($NameWidth)
    $statusText = "[" + $Status + "]"
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

function Format-BravoConsoleMoveLine {
    param(
        [string]$Type,
        [string]$From,
        [string]$To = "",
        [string]$Status = "ПЕРЕМІЩЕНО"
    )

    $width = Get-BravoConsoleWidth
    $prefix = "    $(Get-BravoConsoleBranchPrefix) "
    $typeText = $Type.PadRight(12)

    if ([string]::IsNullOrWhiteSpace($To)) {
        $moveText = "$typeText $From"
    }
    else {
        $moveText = "$typeText $From -> $To"
    }

    $statusText = "[$Status]"
    $dotsCount = $width - $prefix.Length - $moveText.Length - $statusText.Length - 1

    if ($dotsCount -lt 3) {
        $dotsCount = 3
    }

    return $prefix + $moveText + ("." * $dotsCount) + " " + $statusText
}

function Write-BravoConsoleMove {
    param(
        [string]$Type,
        [string]$From,
        [string]$To = "",
        [string]$Status = "ПЕРЕМІЩЕНО",
        [string]$Level = "SUCCESS"
    )

    Write-BravoConsoleRaw -Message (Format-BravoConsoleMoveLine -Type $Type -From $From -To $To -Status $Status) -Level $Level
}

function Write-BravoConsoleInfo {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    Write-BravoConsoleRaw -Message "    $(Get-BravoConsoleBranchPrefix) $Message" -Level $Level
}
function Write-BravoConsoleStep {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    Write-BravoConsoleRaw -Message "    $(Get-BravoConsoleBranchPrefix) $Message" -Level $Level
}

function Write-BravoConsoleFinalLine {
    param(
        [string]$Status,
        [string]$Duration,
        [string]$ObjectName
    )

    $width = Get-BravoConsoleWidth
    $line = "─" * $width

    Write-BravoConsoleSectionSpacing
    Write-BravoConsoleRaw -Message $line -Level "INFO"

    if ($Status -eq "УСПІШНО") {
        $badge = "[ OK ]"
        $badgeColor = "Green"
    }
    else {
        $badge = "[ ERR ]"
        $badgeColor = "Red"
    }

    Write-Host $badge -ForegroundColor $badgeColor -NoNewline
    Write-Host " СТАТУС: $Status | ЧАС: $Duration | УСТАНОВА: $ObjectName" -ForegroundColor White

    Write-BravoConsoleRaw -Message $line -Level "INFO"
}


function Write-BravoLogFileEntry {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [switch]$NoTimestamp
    )

    if ($NoTimestamp) {
        $logEntry = $Message
    }
    else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
    }

    try {
        if (-not (Test-Path $LOG_DIR)) {
            New-Item -ItemType Directory -Path $LOG_DIR -Force | Out-Null
        }

        $logEntry | Out-File -FilePath $LOG_FILE -Append -Encoding UTF8
    }
    catch {
        Write-Host "Помилка запису у файл логу: $($_.Exception.Message)" -ForegroundColor Red
    }
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
    
    # Modern console rendering for legacy Write-Log messages
    if ((Get-BravoConsoleStyle) -eq "modern") {
        if ([string]::IsNullOrWhiteSpace($Message)) {
            Write-BravoConsoleRaw -Message "" -Level "INFO"
            Write-BravoLogFileEntry -Message $Message -Level $Level -NoTimestamp:$NoTimestamp
            return
        }

        if ($Message -eq "=" -or $Message -eq "===") {
            Write-BravoLogFileEntry -Message ("=" * $SeparatorLength) -NoTimestamp
            return
        }

        if ($Message -match "^=== (.+) ===$") {
            $sectionTitle = $Matches[1]

            switch ($sectionTitle) {
                "РЕСТАВРАЦІЯ МОДЕЛІ" {
                    Write-BravoConsoleSection -Icon "Restore" -Title "РЕСТАВРАЦІЯ МОДЕЛІ"
                }
                "ОЧИСТКА СТАРИХ ДАНИХ" {
                    Write-BravoConsoleSection -Icon "Cleanup" -Title "ОЧИСТКА ЗАСТАРІЛИХ ДАНИХ"
                }
                default {
                    Write-BravoConsoleSection -Icon "Info" -Title $sectionTitle
                }
            }

            Write-BravoLogFileEntry -Message $Message -Level $Level -NoTimestamp:$NoTimestamp
            return
        }

        Write-BravoConsoleInfo -Message $Message -Level $Level
        Write-BravoLogFileEntry -Message $Message -Level $Level -NoTimestamp:$NoTimestamp
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








