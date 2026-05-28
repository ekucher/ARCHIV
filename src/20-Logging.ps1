# ==================================================================================================
# BRAVO Logging
# ==================================================================================================

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