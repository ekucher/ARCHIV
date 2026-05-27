##########
# BravoSoft
# Author: Evgeniy Kucher
# Version: 1.2, 2025-10-04 - Slack версія з оновленим логуванням
##########

# Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass –Force

# За потреби запит на підвищення дозволу виконання скрипта
If (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
	Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
	Exit
}

param (
    [switch]$ForceRestore,
    [switch]$DisableSizeCheck,
    [switch]$EnableAllSlack,
    [switch]$DisableAllSlack,
    [string]$AutoShutdown,
    [string]$ArchivLims
)

# Enforce modern security protocol
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Очистка терміналу
clear

# ===== ГЛОБАЛЬНІ НАЛАШТУВАННЯ =====
$global:ObjectName = ""                      # Глобальна змінна для назви об'єкта
$BravoServiceName = "BRAVO"                  # Ім'я служби BravoService
$ExchangAPIServiceName = "exchangAPI"        # Ім'я служби exchangAPI
$ExchangAPIProcessName = "exchangAPI"        # Ім'я процесу (без .exe)
$ArchivePrefix = ""                          # Префікс для архівів
$RestoreDay = 7                              # День реставрації (Число 1-7)
$RestoreTime = "23:00"                       # Час початку реставрації (HH:mm)
$ARCHIVE_RETENTION_DAYS = 14                 # Зберігати архіви днів
$RESTORE_ARCHIVES_KEEP_COUNT = 1             # ЗБЕРІГАТИ ОСТАННІХ ВЕРСІЙ АРХІВІВ РЕСТАВРАЦІЇ
$LOG_RETENTION_DAYS = 180                    # Зберігати логи днів
$MIN_FREE_SPACE = 10                         # Мінімальний вільний простір в GB без одиниць виміру
$MAX_MD_FILE_SIZE = 1.5GB                    # Максимальний розмір .md файлу
$BRAVO_WEB_DIR = "D:\Br-a-vo.web"            # Шлях до директорії Br-a-vo.web

# Перевірка наявності служби Apache в системі
$ApacheService = Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
$ApacheServiceExists = ($ApacheService -ne $null)

# ===== НАЛАШТУВАННЯ АВТОМАТИЧНОГО ВИМКНЕННЯ =====
$AutoShutdown = "off"  # НАЛАШТУВАННЯ: "on" - ввімкнено, "off" - вимкнено
$ShutdownTimeout = 60

$ArchivLims = "off"  # Можливі значення: "on" - запускати ARCHIV_LIMS, "off" - не запускати

# ===== НАЛАШТУВАННЯ SLACK =====
$SlackMode = "errors_only"  # Можливі значення: "none", "errors_only", "all"
$SlackWebhookUrl = ""

# Параметри архіватора (змінювати лише за необхідності)
$arcCommonParams = @('a', '-mmt4', '-mx6', '-r', '-y', '-ssw', '-bb0', '-scrcSHA256', '-aoa', '-pP@ssw0rd')

# ===== НАЛАШТУВАННЯ ЛОГУВАННЯ =====
$LogLevel = "INFO"  # Можливі значента: "DEBUG", "INFO", "WARNING", "ERROR", "SUCCESS"

# ===== ГЛОБАЛЬНІ ЗМІННІ (НЕ ЗМІНЮВАТИ) =====
$global:ScriptStartTime = [DateTime]::Now
$global:SlackMessageBuffer = [System.Collections.Generic.List[string]]::new()
$global:CriticalErrors = $false
$global:CriticalErrorsList = [System.Collections.Generic.List[string]]::new()
$global:criticalErrorOccurred = $false

# Визначаємо режим Slack (НОВА ЛОГІКА) - ЗМІНЕНО: використовуємо глобальне значення за замовчуванням
if ($DisableAllSlack) {
    $script:SlackMode = "none"
    Write-Host "Режим Slack: ВИМКНЕНО (none)" -ForegroundColor Yellow
} elseif ($EnableAllSlack) {
    $script:SlackMode = "all" 
    Write-Host "Режим Slack: УСІ ПОВІДОМЛЕННЯ (all)" -ForegroundColor Green
} else {
    $script:SlackMode = $SlackMode  # Використовуємо глобальне значення за замовчуванням
    #Write-Host "Режим Slack: ВИМКНЕНО (none) - за замовчуванням" -ForegroundColor Yellow
}

# Визначаємо режим автоматичного вимкнення
# Якщо параметр передано через командний рядок - використовуємо його, інакше - значення з налаштувань
if ($PSBoundParameters.ContainsKey('AutoShutdown')) {
    # Використовуємо значення з параметра командного рядка
    $AutoShutdown = $AutoShutdown.ToLower()
} else {
    # Використовуємо значення з налаштувань
    $AutoShutdown = $AutoShutdown.ToLower()
}

if ($AutoShutdown -notin @("on", "off")) {
    Write-Host "ПОМИЛКА: Параметр AutoShutdown має бути 'on' або 'off'. Поточне значення: $AutoShutdown" -ForegroundColor Red
    exit 1
}

$script:EnableAutoShutdown = ($AutoShutdown -eq "on")

# ===== ПЕРЕВІРКА ДЛЯ ARCHIV_LIMS =====
# Якщо параметр передано через командний рядок - використовуємо його, інакше - значення з налаштувань
if ($PSBoundParameters.ContainsKey('ArchivLims')) {
    # Використовуємо значення з параметра командного рядка
    $ArchivLims = $ArchivLims.ToLower()
} else {
    # Використовуємо значення з налаштувань
    $ArchivLims = $ArchivLims.ToLower()
}

if ($ArchivLims -notin @("on", "off")) {
    Write-Host "ПОМИЛКА: Параметр ArchivLims має бути 'on' або 'off'. Поточне значення: $ArchivLims" -ForegroundColor Red
    exit 1
}

$script:EnableArchivLims = ($ArchivLims -eq "on")

# ===== ФУНКЦІЯ ЛОГУВАННЯ =====
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
        Write-Host $logEntry -ForegroundColor White
    } else {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logEntry = "[$timestamp] [$Level] $Message"
        
        switch ($Level) {
            "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
            "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
            "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
            "DEBUG"   { Write-Host $logEntry -ForegroundColor Gray }
            default   { Write-Host $logEntry -ForegroundColor White }
        }
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

# ===== ФУНКЦІЯ АВТОМАТИЧНОГО ВИМКНЕННЯ =====
function Invoke-AutoShutdown {
    param(
        [int]$Timeout = 120
    )
    
    Write-Log -Message "==="
    Write-Log -Message "=== АВТОМАТИЧНЕ ВИМКНЕННЯ СИСТЕМИ ==="

    try {
        # Команда вимкнення
        $shutdownCommand = "shutdown /s /t $Timeout /c `"Система буде вимкнена через $Timeout секунд через завершення обслуговування BravoSoft. Для скасування виконайте: shutdown /a`""
        
        Write-Log -Message "Ініціювання вимкнення системи..." -Level "INFO"
        
        # Запускаємо вимкнення
        $process = Start-Process -FilePath "cmd.exe" -ArgumentList "/c $shutdownCommand" -Wait -PassThru -NoNewWindow
        
        if ($process.ExitCode -eq 0) {
            Write-Log -Message "Система буде вимкнена через $Timeout секунд" -Level "SUCCESS"
            
            # Просте вікно підтвердження
            Add-Type -AssemblyName System.Windows.Forms
            
            $message = "Система буде вимкнена через $Timeout секунд через завершення обслуговування BravoSoft.`n`nБажаєте скасувати вимкнення?"
            $caption = "BravoSoft - Завершення обслуговування"
            $buttons = [System.Windows.Forms.MessageBoxButtons]::YesNo
            $icon = [System.Windows.Forms.MessageBoxIcon]::Question
            
            $result = [System.Windows.Forms.MessageBox]::Show($message, $caption, $buttons, $icon)
            
            if ($result -eq [System.Windows.Forms.DialogResult]::Yes) {
                Write-Log -Message "Користувач скасував вимкнення системи" -Level "INFO"
                
                # Скасовуємо вимкнення
                $cancelProcess = Start-Process "shutdown" -ArgumentList "/a" -Wait -PassThru -NoNewWindow
                
                if ($cancelProcess.ExitCode -eq 0) {
                    Write-Log -Message "Вимкнення успішно скасовано" -Level "SUCCESS"
                    [System.Windows.Forms.MessageBox]::Show("Вимкнення скасовано! Система продовжить роботу.", "BravoSoft", 
                        [System.Windows.Forms.MessageBoxButtons]::OK, 
                        [System.Windows.Forms.MessageBoxIcon]::Information)
                } else {
                    Write-Log -Message "Не вдалося скасувати вимкнення" -Level "ERROR"
                    [System.Windows.Forms.MessageBox]::Show("Не вдалося скасувати вимкнення. Спробуйте виконати команду вручну: shutdown /a", "Помилка", 
                        [System.Windows.Forms.MessageBoxButtons]::OK, 
                        [System.Windows.Forms.MessageBoxIcon]::Warning)
                }
            } else {
                Write-Log -Message "Користувач підтвердив вимкнення системи" -Level "INFO"
                [System.Windows.Forms.MessageBox]::Show("Система буде вимкнена через $Timeout секунд.", "BravoSoft", 
                    [System.Windows.Forms.MessageBoxButtons]::OK, 
                    [System.Windows.Forms.MessageBoxIcon]::Information)
            }
            
        } else {
            Write-Log -Message "Помилка ініціювання вимкнення системи. Код помилки: $($process.ExitCode)" -Level "ERROR"
        }
    }
    catch {
        Write-Log -Message "Помилка під час спроби вимкнення системи: $($_.Exception.Message)" -Level "ERROR"
    }
}

# ===== ДОПОМІЖНІ ФУНКЦІЇ =====

# Функція форматування часу
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

# Перетворення числового дня в об'єкт DayOfWeek
$restoreDayMap = @{
    1 = [DayOfWeek]::Monday
    2 = [DayOfWeek]::Tuesday
    3 = [DayOfWeek]::Wednesday
    4 = [DayOfWeek]::Thursday
    5 = [DayOfWeek]::Friday
    6 = [DayOfWeek]::Saturday
    7 = [DayOfWeek]::Sunday
}
$RestoreDayOfWeek = $restoreDayMap[$RestoreDay]
$RestoreDayName = $RestoreDayOfWeek.ToString()

# Функція відправки Slack сповіщень
function Send-SlackAlert {
    param(
        [string]$Message,
        [switch]$IsCritical
    )
    
    # Перевірка режиму "none" - повне вимкнення всіх повідомлень
    if ($script:SlackMode -eq "none") {
        return
    }
    
    # Автоматично визначаємо критичність для помилок місця
    $isSpaceError = $Message -match "Недостатньо вільного місця|не вистачає місця"
    
    if ($IsCritical -or $isSpaceError) {
        $global:CriticalErrors = $true
        $global:criticalErrorOccurred = $true
        
        # Для критичних помилок перевіряємо режим "errors_only" або "all"
        if ($script:SlackMode -eq "errors_only" -or $script:SlackMode -eq "all") {
            if ($isSpaceError) {
                # Для помилок місця - негайна відправка
                $slackBody = @{
                    text = $Message
                }
                
                try {
                    $jsonBody = $slackBody | ConvertTo-Json -Compress
                    $utf8 = [System.Text.Encoding]::UTF8
                    $bytes = $utf8.GetBytes($jsonBody)
                    
                    $request = [System.Net.WebRequest]::Create($SlackWebhookUrl)
                    $request.Method = "POST"
                    $request.ContentType = "application/json; charset=utf-8"
                    $request.ContentLength = $bytes.Length
                    
                    $stream = $request.GetRequestStream()
                    $stream.Write($bytes, 0, $bytes.Length)
                    $stream.Close()
                    
                    $response = $request.GetResponse()
                    $reader = New-Object System.IO.StreamReader($response.GetResponseStream(), $utf8)
                    $reader.ReadToEnd() | Out-Null
                    $reader.Close()
                    $response.Close()
                    
                    Write-Log "Критичне повідомлення (помилки місця) відправлено в Slack" -Level "INFO"
                }
                catch {
                    Write-Log "ПОМИЛКА негайної відправки: $($_.Exception.Message)" -Level "ERROR"
                }
            }
            else {
                # Для інших критичних помилок - додаємо до списку для групування
                $global:CriticalErrorsList.Add($Message)
            }
        }
    }
    else {
        # Відправляємо не-критичні повідомлення тільки в режимі "all"
        if ($script:SlackMode -ne "all") {
            return
        }
        
        $global:SlackMessageBuffer.Add($Message)
    }
}

# Функція форматування виводу команд
function Format-CommandOutput {
    param([string]$Output)
    return "`n" + ($Output -replace "`r?`n", "`n    ") + "`n"
}

# Функція форматування розміру файлу
function Format-FileSize {
    param([long]$size)
    switch ($size) {
        { $_ -ge 1GB } { return "{0:N2} ГБ" -f ($size / 1GB) }
        { $_ -ge 1MB } { return "{0:N2} МБ" -f ($size / 1MB) }
        { $_ -ge 1KB } { return "{0:N2} КБ" -f ($size / 1KB) }
        default { return "$size байт" }
    }
}

# Функція переміщення файлів з послідовністю
function Move-WithSequence {
    param(
        [string]$sourcePath,
        [string]$destDir,
        [switch]$SkipIfEmpty
    )
    
    if (-not (Test-Path $sourcePath)) {
        Write-Log "[ПОМИЛКА] Файл $([System.IO.Path]::GetFileName($sourcePath)) не знайдено" -Level "ERROR"
        return
    }
    
    $fileInfo = Get-Item $sourcePath
    if ($fileInfo.Length -eq 0 -and $SkipIfEmpty) {
        Write-Log "[ІНФО] Пропущено порожній файл: $([System.IO.Path]::GetFileName($sourcePath))" -Level "INFO"
        return
    }
    
    New-Item -Path $destDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($sourcePath)
    $fileExt = [System.IO.Path]::GetExtension($sourcePath)
    
    $existingFiles = Get-ChildItem -Path $destDir -File -Filter "${fileName}_*$fileExt" -ErrorAction SilentlyContinue
    $maxNumber = 0
    
    foreach ($file in $existingFiles) {
        $baseName = $file.BaseName
        if ($baseName -match "${fileName}_(\d{6})$") {
            $num = [int]$Matches[1]
            if ($num -gt $maxNumber) { $maxNumber = $num }
        }
    }

    $nextNumber = $maxNumber + 1

    if ($nextNumber -gt 999999) {
        Write-Log "[ERROR] Досягнуто максимальну кількість архівних файлів (999999) для $fileName" -Level "ERROR"
        return
    }

    $suffix = $nextNumber.ToString("000000")
    $newName = "${fileName}_${suffix}${fileExt}"
    $destPath = Join-Path -Path $destDir -ChildPath $newName

    try {
        Move-Item -Path $sourcePath -Destination $destPath -Force
        Write-Log "Переміщено $([System.IO.Path]::GetFileName($sourcePath)) до $newName" -Level "SUCCESS"
    }
    catch {
        Write-Log "[ERROR] Помилка переміщення $([System.IO.Path]::GetFileName($sourcePath)): $_" -Level "ERROR"
    }
}

# Функція порівняння розмірів файлів
function Compare-FileSizes {
    param(
        [string]$BeforeFile,
        [string]$ModelPath,
        [int]$MinSizeBytes = 2048
    )
    
    $criticalChanges = $false
    try {
        if (-not (Test-Path $BeforeFile)) {
            Write-Log "Файл з початковими розмірами не знайдено: $BeforeFile" -Level "WARNING"
            return $false
        }

        # Швидке читання CSV з використанням хеш-таблиці
        $sizeLookup = @{}
        $initialData = Import-Csv -Path $BeforeFile
        foreach ($item in $initialData) {
            $sizeLookup[$item.RelativePath] = [long]$item.SizeBytes
        }

        $criticalFiles = @()
        $currentFiles = Get-ChildItem -Path $ModelPath -Recurse -File

        foreach ($file in $currentFiles) {
            $relativePath = $file.FullName.Replace($ModelPath, "").TrimStart('\')
            if ($sizeLookup.ContainsKey($relativePath)) {
                $initialSizeBytes = $sizeLookup[$relativePath]
                $currentSizeBytes = $file.Length
                
                # Порівнюємо лише файли, що змінили розмір
                if ($initialSizeBytes -ne $currentSizeBytes -and 
                    $initialSizeBytes -gt $MinSizeBytes -and 
                    $currentSizeBytes -le $MinSizeBytes) 
                {
                    $criticalFiles += [PSCustomObject]@{
                        File = $relativePath
                        BeforeSizeBytes = $initialSizeBytes
                        AfterSizeBytes = $currentSizeBytes
                    }
                    $criticalChanges = $true
                }
            }
        }

        if ($criticalFiles.Count -gt 0) {
            $criticalMessage = "Знайдено $($criticalFiles.Count) файлів з критичною зміною розміру після реставрації:`n"
            foreach ($file in $criticalFiles) {
                $beforeFormatted = Format-FileSize $file.BeforeSizeBytes
                $afterFormatted = Format-FileSize $file.AfterSizeBytes
                $reductionPercent = ($file.BeforeSizeBytes - $file.AfterSizeBytes) / $file.BeforeSizeBytes * 100
                
                $criticalMessage += " - $($file.File):`n"
                $criticalMessage += "   Розмір до реставрації: $beforeFormatted ($($file.BeforeSizeBytes) байт)`n"
                $criticalMessage += "   Розмір після реставрації: $afterFormatted ($($file.AfterSizeBytes) байт)`n"
                $criticalMessage += "   Статус: ❌ РЕДУКЦІЯ (зменшено на $($reductionPercent.ToString('0.00'))%)`n"
            }
            
            Write-Log $criticalMessage -Level "ERROR"
            Send-SlackAlert -Message $criticalMessage -IsCritical
            $global:criticalErrorOccurred = $true
            
            return $true
        } else {
            Write-Log "Змін в розмірах файлів не знайдено" -Level "INFO"
            return $false
        }
    }
    catch {
        $errorMsg = "Помилка при порівнянні розмірів файлів: $_"
        Write-Log $errorMsg -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
        return $false
    }
}

# Функція відновлення з архіву (для відкату при помилках)
function Restore-FromArchive {
    param(
        [string]$ArchivePath,
        [string]$Destination,
        $ARC_PATH
    )
    
    if (-not (Test-Path $ArchivePath)) {
        $errorMsg = "Архів для відновлення не знайдено: $ArchivePath"
        Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
        return 1
    }

    $extractParams = @(
        'x',
        "-o$Destination",
        "-pP@ssw0rd",
        "-y",
        $ArchivePath
    )
    
    $exitCode = Invoke-CommandWithLog -Command $ARC_PATH -Arguments $extractParams -Description "Відновлення моделі з архіву"
    
    if ($exitCode -eq 0) {
        Write-Log "Модель успішно відновлена з архіву: $([System.IO.Path]::GetFileName($ArchivePath))" -Level "SUCCESS"
    } else {
        $errorMsg = "Не вдалося відновити модель з архіву! Код помилки: $exitCode"
        Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
    }
    
    return $exitCode
}

# Функція виконання команд з логуванням
function Invoke-CommandWithLog {
    param(
        [string]$Command,
        [array]$Arguments,
        [string]$Description
    )
    
    Write-Log "$Description..." -Level "INFO"
    $output = & $Command $Arguments 2>&1 | Out-String
    $formattedOutput = Format-CommandOutput -Output $output
    
    if ($LASTEXITCODE -eq 0) {
        Write-Log "$Description успішно завершено" -Level "SUCCESS"
    } else {
        $errorMsg = "ПОМИЛКА під час $Description. Код: $LASTEXITCODE"
        Write-Log $errorMsg -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
    }
    
    if (-not [string]::IsNullOrWhiteSpace($formattedOutput)) {
        Write-Log "Деталі виконання:$formattedOutput" -Level "DEBUG"
    }
    
    return $LASTEXITCODE
}

# Функція обробки лог-файлів
function Process-Logs {
    param(
        [string]$LogType,
        [string]$SourceDir,
        [string]$DestDir
    )
    
    if (-not (Test-Path $SourceDir)) {
        Write-Log "[ПОМИЛКА] Директорія $SourceDir не знайдена. Обробка логів $LogType пропущена." -Level "ERROR"
        return
    }
    
    $logFiles = Get-ChildItem -Path $SourceDir -File -ErrorAction SilentlyContinue | 
        Where-Object { $_.Length -gt 0 }
    
    if (-not $logFiles) {
        Write-Log "[ІНФО] У директорії $SourceDir немає файлів логів для обробки ($LogType)." -Level "INFO"
        return
    }
    
    New-Item -Path $DestDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    
    foreach ($file in $logFiles) {
        Move-WithSequence -sourcePath $file.FullName -destDir $DestDir -SkipIfEmpty
    }
    Write-Log "Оброблено $($logFiles.Count) $LogType файлів" -Level "SUCCESS"
}

# Функція архівації старих даних
function Compress-OldData {
    param(
        [string]$ParentPath,
        [string]$ArchiveNamePrefix,
        [int]$RetentionDays,
        $arcCommonParams,
        $ARC_PATH
    )
    
    if (-not (Test-Path $ParentPath)) {
        Write-Log "[ПОМИЛКА] Директорія $ParentPath не знайдена. Архівація пропущена." -Level "ERROR"
        return
    }
    
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $oldDirs = Get-ChildItem -Path $ParentPath -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.CreationTime -lt $cutoffDate }
    
    if (-not $oldDirs) {
        Write-Log "Немає старих директорій для архівації у $ParentPath" -Level "DEBUG"
        return
    }

    $archivedCount = 0
    $errorCount = 0

    foreach ($dir in $oldDirs) {
        $dirName = $dir.Name
        $archiveName = "${ArchiveNamePrefix}_$dirName.mdz"
        $archivePath = Join-Path -Path $ParentPath -ChildPath $archiveName
        
        try {
            Write-Log "Архівація: $dirName -> $archiveName" -Level "INFO"
            $arcArgs = $arcCommonParams + @("$archivePath", "$($dir.FullName)")
            $exitCode = Invoke-CommandWithLog -Command $ARC_PATH -Arguments $arcArgs -Description "Архівація $dirName"
            
            if ($exitCode -eq 0) {
                Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
                $archivedCount++
                Write-Log "[ІНФО] Архів $dirName успішно створено" -Level "SUCCESS"
            } else {
                $errorCount++
            }
        }
        catch {
            $errorCount++
            Write-Log "ПОМИЛКА при архівації ${dirName}: $($_.Exception.Message)" -Level "ERROR"
        }
    }
    
    if ($archivedCount -gt 0) {
        Write-Log "[ІНФО] Архівовано $archivedCount директорій" -Level "SUCCESS"
    }
    if ($errorCount -gt 0) {
        $errorMsg = "Виникло $errorCount помилок під час архівації"
        Write-Log "[ПОМИЛКА] $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg
        $global:criticalErrorOccurred = $true
    }
}

# Функція видалення старих директорій
function Remove-OldDirectories {
    param(
        [string]$Path,
        [int]$RetentionDays
    )

    if (-not (Test-Path $Path)) {
        Write-Log "[ПОМИЛКА] Директорія $Path не знайдена. Видалення пропущено." -Level "ERROR"
        return
    }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $oldDirs = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.CreationTime -lt $cutoffDate }

    if (-not $oldDirs) {
        Write-Log "Немає старих директорій для видалення у $Path" -Level "DEBUG"
        return
    }

    $deletedCount = 0
    $errorCount = 0

    foreach ($dir in $oldDirs) {
        try {
            Write-Log "Видалення $($dir.FullName)..." -Level "DEBUG"
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
            $deletedCount++
            Write-Log "Директорію $($dir.Name) успішно видалено" -Level "SUCCESS"
        }
        catch {
            $errorCount++
            Write-Log "ПОМИЛКА при видаленні $($dir.Name): $($_.Exception.Message)" -Level "ERROR"
        }
    }

    if ($deletedCount -gt 0) {
        Write-Log "[ІНФО] Видалено $deletedCount директорій" -Level "SUCCESS"
    }
    if ($errorCount -gt 0) {
        $errorMsg = "Виникло $errorCount помилок під час видалення"
        Write-Log "[ПОМИЛКА] $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg
        $global:criticalErrorOccurred = $true
    }
}

# Функція видалення старих лог-файлів
function Remove-OldLogFiles {
    param(
        [string]$Path,
        [int]$RetentionDays
    )

    if (-not (Test-Path $Path)) {
        Write-Log "[ІНФО] Директорія логів $Path не знайдена. Видалення пропущено." -Level "INFO"
        return
    }

    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    # Включаємо всі типи лог-файлів: скрипти, розміри файлів, маркери
    $oldFiles = Get-ChildItem -Path $Path -File -ErrorAction SilentlyContinue | 
        Where-Object { 
            $_.CreationTime -lt $cutoffDate -and 
            ($_.Name -like "script_log_*.txt" -or 
             $_.Name -like "file_sizes_*.csv" -or 
             $_.Name -like "restore_done_*.marker")
        }

    if (-not $oldFiles) {
        Write-Log "Немає старих лог-файлів для видалення у $Path" -Level "DEBUG"
        return
    }

    $deletedCount = 0
    $errorCount = 0

    foreach ($file in $oldFiles) {
        try {
            Remove-Item -Path $file.FullName -Force -ErrorAction Stop
            $deletedCount++
            Write-Log "Видалено лог-файл: $($file.Name)" -Level "SUCCESS"
        }
        catch {
            $errorCount++
            Write-Log "ПОМИЛКА при видаленні $($file.Name): $($_.Exception.Message)" -Level "ERROR"
        }
    }

    if ($deletedCount -gt 0) {
        Write-Log "[ІНФО] Видалено $deletedCount старих лог-файлів" -Level "SUCCESS"
    }
    if ($errorCount -gt 0) {
        $errorMsg = "Виникло $errorCount помилок під час видалення лог-файлів"
        Write-Log "[ПОМИЛКА] $errorMsg" -Level "ERROR"
    }
}

# Функція обробки старих даних
function Process-OldData {
    param(
        [string]$Path,
        [string]$ArchiveNamePrefix,
        [int]$RetentionDays,
        $arcCommonParams,
        $ARC_PATH
    )
    
    # Архівація старих даних
    Compress-OldData -ParentPath $Path -ArchiveNamePrefix $ArchiveNamePrefix -RetentionDays $RetentionDays -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH
    
    # Видалення старих директорій
    Remove-OldDirectories -Path $Path -RetentionDays $RetentionDays
}

# Функція видалення старих архівів реставрації (за кількістю версій)
function Remove-OldRestoreArchives {
    param(
        [string]$Path,
        [string]$ArchivePrefix,
        [int]$KeepCount = 2
    )

    if (-not (Test-Path $Path)) {
        Write-Log "[ІНФО] Директорія архівів $Path не знайдена. Видалення пропущено." -Level "DEBUG"
        return
    }

    # Шаблони для пошуку основних архівів (без .sha512)
    $mainArchivePatterns = @(
        "${ArchivePrefix}_before_*.mdz",
        "${ArchivePrefix}_after_*.mdz"
    )

    # Збираємо основні архіви (без контрольних сум)
    $mainArchiveFiles = $mainArchivePatterns | ForEach-Object {
        Get-ChildItem -Path $Path -Filter $_ -ErrorAction SilentlyContinue
    }

    if (-not $mainArchiveFiles -or $mainArchiveFiles.Count -eq 0) {
        Write-Log "Немає основних архівів реставрації для обробки у $Path" -Level "DEBUG"
        return
    }

    $archiveGroups = $mainArchiveFiles | Group-Object { 
        if ($_.Name -match "${ArchivePrefix}_(before|after)_(\d{8}_\d{4})\.mdz") {
            $Matches[2]
        } else {
            $_.CreationTime.ToString("yyyyMMdd_HHmm")
        }
    }

    $sortedGroups = $archiveGroups | Sort-Object Name -Descending
    $groupsToKeep = $sortedGroups | Select-Object -First $KeepCount
    $groupsToDelete = $sortedGroups | Select-Object -Skip $KeepCount

    if ($groupsToDelete.Count -eq 0) {
        # Не виводимо повідомлення, якщо немає що видаляти
        return
    }

    Write-Log "Знайдено $($mainArchiveFiles.Count) архівів реставрації" -Level "INFO"
    Write-Log "Зберігаємо $($groupsToKeep.Count) найсвіжіших сесій архівів, видаляємо $($groupsToDelete.Count) найстаріших сесій" -Level "INFO"

    # Показуємо які сесії зберігаємо (тільки в режимі DEBUG)
    Write-Log "Сесії для збереження (найсвіжіші):" -Level "DEBUG"
    foreach ($group in $groupsToKeep) {
        $sessionTime = $group.Name
        $beforeCount = ($group.Group | Where-Object { $_.Name -like "*_before_*" }).Count
        $afterCount = ($group.Group | Where-Object { $_.Name -like "*_after_*" }).Count
        Write-Log "  - $sessionTime (before: $beforeCount, after: $afterCount)" -Level "DEBUG"
    }

    $deletedCount = 0
    $errorCount = 0

    # Видаляємо найстаріші сесії (всі файли пов'язані з цими сесіями)
    foreach ($group in $groupsToDelete) {
        $sessionTime = $group.Name
        Write-Log "Видалення сесії: $sessionTime ($($group.Count) файлів)..." -Level "INFO"
        
        # Видаляємо всі файли цієї сесії (основні архіви та контрольні суми)
        $sessionFiles = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.Name -match "${ArchivePrefix}_(before|after)_${sessionTime}" 
            }
        
        foreach ($file in $sessionFiles) {
            try {
                Write-Log "  Видалення: $($file.Name)..." -Level "DEBUG"
                Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                $deletedCount++
                Write-Log "  Старий архів видалено: $($file.Name)" -Level "SUCCESS"
            }
            catch {
                $errorCount++
                Write-Log "  ПОМИЛКА при видаленні $($file.Name): $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }

    # Логуємо результати
    if ($deletedCount -gt 0) {
        Write-Log "[ІНФО] Видалено $deletedCount файлів зі старих сесій архівів (збережено $KeepCount найсвіжіших сесій)" -Level "SUCCESS"
        
        # Показуємо що залишилось (тільки в режимі DEBUG)
        $remainingFiles = Get-ChildItem -Path $Path -Filter "${ArchivePrefix}_*" -ErrorAction SilentlyContinue
        if ($remainingFiles) {
            Write-Log "Залишилось архівів: $($remainingFiles.Count)" -Level "DEBUG"
            foreach ($file in $remainingFiles) {
                Write-Log "  - $($file.Name)" -Level "DEBUG"
            }
        }
    }
    
    if ($errorCount -gt 0) {
        $errorMsg = "Виникло $errorCount помилок під час видалення старих архівів"
        Write-Log "[ПОМИЛКА] $errorMsg" -Level "ERROR"
    }
}

# ===== ФУНКЦІЯ ПЕРЕВІРКИ ВІЛЬНОГО МІСЦЯ =====
function Check-FreeSpace {
    param(
        $ROOT_LIMS
    )
    
    $currentTime = Get-Date
    $elapsedTime = $currentTime - $global:ScriptStartTime
    $datePart = $currentTime.ToString('dd MMMM yyyy')
    $timePart = $currentTime.ToString('HH:mm:ss')
    $durationText = Format-Duration $elapsedTime
    
    Write-Log "Перевірка вільного місця на диску..." -Level "DEBUG"
    
    try {
        if (-not (Test-Path $ROOT_LIMS)) {
            $errorMsg = "Шлях $ROOT_LIMS не існує або недоступний"
            Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
            # В режимі "none" не відправляємо повідомлення
            if ($script:SlackMode -ne "none") {
                $slackMsg = "🚨 КРИТИЧНА ПОМИЛКА:`n🏚️ Установа: $($global:ObjectName)`n🗓️ Дата: $datePart`n⏰ Час: $timePart`n⏳ Тривалість: $durationText`n📌 Деталі: $errorMsg"
                Send-SlackAlert -Message $slackMsg -IsCritical
            }
            $global:criticalErrorOccurred = $true
            return $false
        }

        # Визначаємо кореневий диск
        $rootDrive = [System.IO.Path]::GetPathRoot($ROOT_LIMS)
        
        Write-Log "Перевіряємо диск: $rootDrive" -Level "DEBUG"
        
        # Використовуємо DriveInfo для надійної перевірки
        $driveInfo = [System.IO.DriveInfo]::GetDrives() | Where-Object { 
            $_.RootDirectory.Name -eq $rootDrive -and $_.IsReady
        } | Select-Object -First 1
        
        if (-not $driveInfo) {
            $errorMsg = "Диск $rootDrive не знайдено або не готовий"
            Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
            # В режимі "none" не відправляємо повідомлення
            if ($script:SlackMode -ne "none") {
                $slackMsg = "🚨 КРИТИЧНА ПОМИЛКА:`n🏚️ Установа: $($global:ObjectName)`n🗓️ Дата: $datePart`n⏰ Час: $timePart`n⏳ Тривалість: $durationText`n📌 Деталі: $errorMsg"
                Send-SlackAlert -Message $slackMsg -IsCritical
            }
            $global:criticalErrorOccurred = $true
            return $false
        }

        # Отримуємо вільне місце
        $freeSpaceGB = [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)
        $totalSpaceGB = [math]::Round($driveInfo.TotalSize / 1GB, 2)
        
        # Одне повідомлення з потрібним форматом
        $logMessage = "Доступно вільного місця: $freeSpaceGB GB з $totalSpaceGB GB (Потрібно мінімум: $MIN_FREE_SPACE GB)"
        Write-Log $logMessage -Level "INFO"
        
        if ($freeSpaceGB -lt $MIN_FREE_SPACE) {
            $errorMsg = "Недостатньо вільного місця на диску! Залишилось ${freeSpaceGB} GB, потрібно мінімум ${MIN_FREE_SPACE} GB"
            Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
            
            # В режимі "none" не відправляємо повідомлення
            if ($script:SlackMode -ne "none") {
                $slackMsg = "🚨 КРИТИЧНА ПОМИЛКА:`n🏚️ Установа: $($global:ObjectName)`n🗓️ Дата: $datePart`n⏰ Час: $timePart`n⏳ Тривалість: $durationText`n📌 Деталі: $errorMsg"
                Send-SlackAlert -Message $slackMsg -IsCritical
            }
            
            $global:criticalErrorOccurred = $true
            return $false
        }
        else {
            if ($script:SlackMode -eq "all") {
                $infoMsg = "Достатньо вільного місця на диску: ${freeSpaceGB} GB (мінімум ${MIN_FREE_SPACE} GB)"
                $slackMsg = "💾 Інформація:`n🏚️ Установа: $($global:ObjectName)`n🗓️ Дата: $datePart`n⏰ Час: $timePart`n⏳ Тривалість: $durationText`n📌 Деталі: $infoMsg"
                Send-SlackAlert -Message $slackMsg
            }
            return $true
        }
    }
    catch {
        $errorMsg = "Помилка перевірки місця: $($_.Exception.Message)"
        Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
        # В режимі "none" не відправляємо повідомлення
        if ($script:SlackMode -ne "none") {
            $slackMsg = "🚨 КРИТИЧНА ПОМИЛКА:`n🏚️ Установа: $($global:ObjectName)`n🗓️ Дата: $datePart`n⏰ Час: $timePart`n⏳ Тривалість: $durationText`n📌 Деталі: $errorMsg"
            Send-SlackAlert -Message $slackMsg -IsCritical
        }
        $global:criticalErrorOccurred = $true
        return $false
    }
}

# Функція перевірки контрольних сум архіву
function Verify-Backup {
    param(
        [string]$ArchivePath
    )
    
    Write-Log "Перевірка контрольних сум архіву: $([System.IO.Path]::GetFileName($ArchivePath))" -Level "INFO"
    
    if (-not (Test-Path $ArchivePath)) {
        $errorMsg = "Архів не знайдено: $ArchivePath"
        Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
        $global:criticalErrorOccurred = $true
        return $false
    }

    $shaFile = "$ArchivePath.sha512"
    $fileName = [System.IO.Path]::GetFileName($ArchivePath)
    $valid = $true

    try {
        # Генерація контрольної суми
        $hash = (Get-FileHash -Path $ArchivePath -Algorithm SHA512).Hash.ToUpper()
        "$hash *$fileName" | Out-File -FilePath $shaFile -Encoding ASCII
        
        # Повний шлях до архіву без зайвого розширення
        Write-Log "Контрольна сума архіву збережена для -> $ArchivePath" -Level "SUCCESS"
    }
    catch {
        Write-Log "ПОМИЛКА: Помилка перевірки архіву $fileName - $($_.Exception.Message)" -Level "ERROR"
        $valid = $false
    }

    return $valid
}

# Функція перевірки розмірів .md файлів
function Check-MdFileSizes {
    param(
        $MODEL_PATH,
        $MAX_MD_FILE_SIZE
    )
    
    Write-Log "==="
    Write-Log "=== ПЕРЕВІРКА РОЗМІРІВ .MD ФАЙЛІВ ==="
    Write-Log "Перевірка розмірів файлів .md..." -Level "INFO"
    
    $largeFiles = Get-ChildItem -Path $MODEL_PATH -Recurse -Filter *.md | 
                  Where-Object { $_.Length -gt $MAX_MD_FILE_SIZE }

    if ($largeFiles) {
        # Формуємо список файлів через StringBuilder
        $fileListBuilder = [System.Text.StringBuilder]::new()
        foreach ($file in $largeFiles) {
            $sizeFormatted = Format-FileSize $file.Length
            $relativePath = $file.FullName.Replace($MODEL_PATH, "").TrimStart('\')
            [void]$fileListBuilder.AppendLine("- $relativePath : $sizeFormatted")
        }
        $fileList = $fileListBuilder.ToString()

        $message = "Знайдено $($largeFiles.Count) файлів .md, розмір яких перевищує $($MAX_MD_FILE_SIZE / 1MB) МБ:`n$fileList"
        Write-Log $message -Level "WARNING"
        Send-SlackAlert -Message $message -IsCritical
    } else {
        Write-Log "Файли .md з розміром більше $($MAX_MD_FILE_SIZE / 1MB) МБ не знайдено." -Level "INFO"
    }
}

# Функція обробки логів ExchangAPI
function Move-ExchangAPILogs {
    param(
        [string]$sourcePath,
        [string]$destDir
    )
    
    if (-not (Test-Path $sourcePath)) {
        Write-Log "[ПОМИЛКА] Файл $([System.IO.Path]::GetFileName($sourcePath)) не знайдено" -Level "ERROR"
        return
    }
    
    New-Item -Path $destDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    
    $destPath = Join-Path -Path $destDir -ChildPath ([System.IO.Path]::GetFileName($sourcePath))
    
    try {
        Move-Item -Path $sourcePath -Destination $destPath -Force
        Write-Log "Переміщено $([System.IO.Path]::GetFileName($sourcePath)) до $destDir" -Level "SUCCESS"
    }
    catch {
        Write-Log "[ERROR] Помилка переміщення $([System.IO.Path]::GetFileName($sourcePath)): $_" -Level "ERROR"
    }
}

# Функція для відправки фінального звіту
function Send-FinalReport {
    param(
        $LOG_FILE
    )
    
    # Перевірка режиму "none" - повне вимкнення
    if ($script:SlackMode -eq "none") {
        return
    }
    
    $currentTime = Get-Date
    $elapsedTime = $currentTime - $global:ScriptStartTime
    $datePart = $currentTime.ToString('dd MMMM yyyy')
    $timePart = $currentTime.ToString('HH:mm:ss')
    $durationText = Format-Duration $elapsedTime
    
    # Формуємо основне повідомлення
    $slackMsg = ""
    $shouldSend = $false
    
    if ($global:CriticalErrorsList.Count -gt 0) {
        # Є критичні помилки - відправляємо в режимах "errors_only" та "all"
        $errorDetails = $global:CriticalErrorsList -join "`n - "
        $slackMsg = "🚨 КРИТИЧНІ ПОМИЛКИ:`n" +
                   "🏚️ Установа: $($global:ObjectName)`n" +
                   "🗓️ Дата: $datePart`n" +
                   "⏰ Час: $timePart`n" +
                   "⏳ Тривалість виконання: $durationText`n" +
                   "📌 Деталі подій:`n - $errorDetails"
        
        $shouldSend = $true
    } 
    else {
        # Немає критичних помилок - відправляємо тільки в режимі "all"
        if ($script:SlackMode -eq "all") {
            $slackMsg = "✅ СКРИПТ УСПІШНО ВИКОНАНО`n" +
                       "🏚️ Установа: $($global:ObjectName)`n" +
                       "🗓️ Дата: $datePart`n" +
                       "⏰ Час: $timePart`n" +
                       "⏳ Тривалість виконання: $durationText"
            
            $shouldSend = $true
        } else {
            # Режим "errors_only" - не відправляємо успішні повідомлення, просто виходимо
            return
        }
    }
    
    # Якщо повідомлення не повинно відправлятися - виходимо
    if (-not $shouldSend) {
        return
    }
    
    # Додаємо шлях до лог-файлу
    $slackMsg += "`n📝Лог: $LOG_FILE"
    
    # Показуємо заголовок тільки якщо відправка дійсно відбувається
    Write-Log -Message "==="
    Write-Log -Message "=== ВІДПРАВКА ПОВІДОМЛЕННЯ ПРО ПОДІЮ ==="
    Write-Log -Message "Відправка повідомлення в Slack" -Level "INFO"
    
    $slackBody = @{
        text = $slackMsg
    }
    
    # Додаткові налаштування для коректної серіалізації
    $jsonSettings = @{
        Depth = 10
        Compress = $true
    }
    
    try {
        # Використовуємо WebClient для більш стабільної роботи
        $webClient = New-Object System.Net.WebClient
        $webClient.Encoding = [System.Text.Encoding]::UTF8
        $webClient.Headers.Add("Content-Type", "application/json")
        
        $jsonBody = $slackBody | ConvertTo-Json @jsonSettings
        $response = $webClient.UploadString($SlackWebhookUrl, "POST", $jsonBody)
        
        Write-Log -Message "Фінальне повідомлення відправлено в Slack" -Level "SUCCESS"
    }
    catch {
        $errorDetails = $_.Exception.Message
        if ($_.ErrorDetails) {
            $errorDetails += " | Response: " + $_.ErrorDetails
        }
        Write-Log -Message "ПОМИЛКА відправки фінального повідомлення: $errorDetails" -Level "ERROR"
    }
    
    Write-Log -Message "==="
}

# ===== ОСНОВНИЙ КОД СКРИПТУ =====

# Перевірити права адміна
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ЗАПУСТІТЬ СКРИПТ ВІД ІМЕНІ АДМІНІСТРАТОРА!" -ForegroundColor Red
    exit 1
}

# Перевірка версії PowerShell
if ($PSVersionTable.PSVersion.Major -lt 5 -or ($PSVersionTable.PSVersion.Major -eq 5 -and $PSVersionTable.PSVersion.Minor -lt 1)) {
    Write-Host "ПОМИЛКА: Необхідна версія PowerShell 5.1 або вище. Поточна версія: $($PSVersionTable.PSVersion)" -ForegroundColor Red
    exit 1
}

# Перевірка архітектури ОС
if (-not [Environment]::Is64BitOperatingSystem) {
    Write-Host "ПОМИЛКА: Скрипт працює тільки на 64-бітних системах" -ForegroundColor Red
    exit 1
}

# Перевірка версії ОС
$osVersion = [System.Environment]::OSVersion.Version
if ($osVersion.Major -lt 6 -or ($osVersion.Major -eq 6 -and $osVersion.Minor -lt 3)) {
    Write-Host "ПОМИЛКА: Скрипт вимагає Windows 8.1/Windows Server 2012 R2 або новішої версії" -ForegroundColor Red
    exit 1
}

# Автоматична перевірка наявності директорії BRAVO_WEB
$ApacheEnabled = $false
if ($ApacheServiceExists -and (Test-Path $BRAVO_WEB_DIR)) {
    $Apache = "$BRAVO_WEB_DIR\apache\bin\httpd.exe"
    
    # Перевірка наявності Apache та лог-директорій
    $ApacheExists = Test-Path $Apache
    $ApacheLogsExist = (Test-Path "$BRAVO_WEB_DIR\apache\logs") -and (Test-Path "$BRAVO_WEB_DIR\www\log")
    $ApacheEnabled = $ApacheExists -and $ApacheLogsExist
    if (-not $ApacheEnabled) {
        Write-Host "Apache не знайдено або відсутні лог-директорії - обробка логів вимкнена"
    }
}

# Автоматичне визначення кореня LIMS
$scriptPath = $PSScriptRoot
if (-not $scriptPath) { $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path }

if ((Split-Path -Leaf $scriptPath) -ne "ARCHIV") {
    $errorMessage = "ПОМИЛКА: Скрипт має запускатись лише з папки ARCHIV!"
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $errorMessage" | Out-File "$env:TEMP\lims_error.log" -Append
    Write-Host $errorMessage -ForegroundColor Red
    exit 1
}

$ROOT_LIMS = Split-Path -Parent $scriptPath
$ExchangAPIExePath = "$ROOT_LIMS\exchangAPI.exe"  # Шлях до exchangAPI.exe

# Похідні шляхи
$MODEL_PATH = "$ROOT_LIMS\Model"
$LOG_DIR = "$ROOT_LIMS\ARCHIV\LOGS"
$TRACE_DIR = "$ROOT_LIMS\ARCHIV\Trace"
$ARC_DIR = "$ROOT_LIMS\ARCHIV\LIMS"
$ARC_PATH = "$ROOT_LIMS\ARCHIV\Tools\7za.exe"   # Шлях до архіватора
$EXCHANGAPI_ARCHIV_DIR = "$ROOT_LIMS\ARCHIV\exchangAPI"

if ($ApacheServiceExists -and $ApacheEnabled) {
    $BRAVO_WEB_ARCHIV_DIR = "$ROOT_LIMS\ARCHIV\Br-a-vo.web"
    $APACHE_LOGS_DIR = "$BRAVO_WEB_DIR\apache\logs"
    $WWW_LOGS_DIR = "$BRAVO_WEB_DIR\www\log"
}

# Переконатися, що директорія логів існує
if (-not (Test-Path $LOG_DIR)) {
    try {
        New-Item -Path $LOG_DIR -ItemType Directory -Force | Out-Null
        Write-Host "Створено директорію для логів: $LOG_DIR" -ForegroundColor Green
    }
    catch {
        Write-Host "Не вдалося створити директорію для логів $LOG_DIR : $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# Ініціалізація дати
$currentDate = Get-Date
$NOW = $currentDate.ToString("yyyyMMdd_HHmm")
$YYYY = $currentDate.Year.ToString("0000")
$MM = $currentDate.Month.ToString("00")
$DD = $currentDate.Day.ToString("00")

# Похідні параметри
$isRestoreDay = ($currentDate.DayOfWeek -eq $RestoreDayOfWeek)
$restoreTimeSpan = [TimeSpan]::Parse($RestoreTime)
$isAfterRestoreTime = ($currentDate.TimeOfDay -ge $restoreTimeSpan)

# Визначаємо MARKER_FILE до використання в shouldRestore
$MARKER_FILE = "$LOG_DIR\restore_done_$YYYY$MM$DD.marker"

$shouldRestore = $ForceRestore -or ($isRestoreDay -and $isAfterRestoreTime -and -not (Test-Path $MARKER_FILE))
$restoreReason = if ($ForceRestore) { "Примусово" } else { "$RestoreDayName, після $RestoreTime" }
$CheckSize = -not $DisableSizeCheck

# Похідні файлові шляхи
$ARCH_NAME1 = "${ArchivePrefix}_before_$NOW.mdz"
$ARCH_NAME2 = "${ArchivePrefix}_after_$NOW.mdz"
$LOG_FILE = "$LOG_DIR\script_log_$NOW.txt"
$SIZES_FILE = "$LOG_DIR\file_sizes_before_$NOW.csv"
$TRACE_ARCHIV_DIR = "$TRACE_DIR\$YYYY-$MM-$DD"

# ===== СТВОРЕННЯ НЕОБХІДНИХ ДИРЕКТОРІЙ =====
# ===== ПОЧАТОК ВИКОНАННЯ =====
Write-Log -Message "==="
Write-Log -Message "=== СИСТЕМА ОБСЛУГОВУВАННЯ BRAVOSOFT ЗАПУЩЕНА ==="
Write-Log -Message "=== УСТАНОВА: $($global:ObjectName) ==="
Write-Log -Message "==="
Write-Log -Message "Коренева директорія: $ROOT_LIMS" -NoTimestamp
Write-Log -Message "Дата: $($currentDate.ToString('yyyy-MM-dd'))" -NoTimestamp
Write-Log -Message "Час: $($currentDate.ToString('HH:mm:ss'))" -NoTimestamp
Write-Log -Message "Налаштування Slack: Режим $(switch ($script:SlackMode) {'none' {'ВИМКНЕНО'} 'errors_only' {'ЛИШЕ ПОМИЛКИ'} 'all' {'УСІ ПОВІДОМЛЕННЯ'}})" -NoTimestamp

# Показуємо статус автоматичного вимкнення тільки якщо воно УВІМКНЕНО
if ($script:EnableAutoShutdown) {
    Write-Log -Message "Автоматичне вимкнення: УВІМКНЕНО" -NoTimestamp
}

# Відображаємо інформацію про Apache тільки якщо служба існує
if ($ApacheServiceExists) {
    Write-Log -Message "Наявність Apache: $(if ($ApacheEnabled) {'Увімкнено'} else {'Вимкнено'})" -NoTimestamp
}

if ($isRestoreDay -and $isAfterRestoreTime -and (Test-Path $MARKER_FILE)) {
    Write-Log -Message "РЕСТАВРАЦІЯ СЬОГОДНІ ВЖЕ ВИКОНУВАЛАСЬ (знайдено маркер $([System.IO.Path]::GetFileName($MARKER_FILE)))" -Level "INFO"
}

Write-Log -Message "Реставрація моделі: $(if ($shouldRestore) {"АКТИВОВАНА ($restoreReason)"} else {"ВИМКНЕНА"})" -NoTimestamp
Write-Log -Message "Перевірка розмірів файлів: $(if ($CheckSize) {'УВІМКНЕНО'} else {'ВИМКНЕНО'})" -NoTimestamp
Write-Log -Message "Умови: заданий день=$isRestoreDay, після $RestoreTime=$isAfterRestoreTime" -NoTimestamp
Write-Log -Message "==="
Write-Log -Message "=== ПЕРЕВІРКА ВІЛЬНОГО МІСЦЯ ==="
$spaceCheckResult = Check-FreeSpace -ROOT_LIMS $ROOT_LIMS

# Перевірка критичних помилок після перевірки місця
if (-not $spaceCheckResult) {
    Write-Log -Message "Критична помилка перевірки місця. Завершення скрипта." -Level "ERROR"
    exit 1
}

# ===== СТВОРЕННЯ НЕОБХІДНИХ ДИРЕКТОРІЙ =====
# Перевіряємо, чи потрібно створювати будь-які директорії
$dirsToCreate = @($TRACE_DIR, $ARC_DIR, $TRACE_ARCHIV_DIR, $EXCHANGAPI_ARCHIV_DIR)
if ($ApacheServiceExists -and $ApacheEnabled) {
    $BRAVO_WEB_DAILY_DIR = "$BRAVO_WEB_ARCHIV_DIR\$YYYY-$MM-$DD"
    $dirsToCreate += $BRAVO_WEB_ARCHIV_DIR, $BRAVO_WEB_DAILY_DIR
}

# Перевіряємо, які директорії потрібно створити
$missingDirs = $dirsToCreate | Where-Object { -not (Test-Path $_) }

if ($missingDirs.Count -gt 0 -or $global:criticalErrorOccurred) {
    Write-Log -Message "==="
    Write-Log -Message "=== СТВОРЕННЯ НЕОБХІДНИХ ДИРЕКТОРІЙ ==="

    $createdDirs = [System.Collections.Generic.List[string]]::new()
    foreach ($dir in $dirsToCreate) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Log -Message "Створено директорію: $dir" -Level "SUCCESS"
                $createdDirs.Add($dir)
            }
            catch {
                $errorMsg = "Не вдалося створити директорію $dir : $($_.Exception.Message)"
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            }
        }
    }

    # Показуємо повідомлення тільки якщо були створені директорії
    if ($createdDirs.Count -gt 0) {
        Write-Log -Message "Створено $($createdDirs.Count) директорій" -Level "SUCCESS"
    }
}

# ===== ЗУПИНКА СЛУЖБ =====
Write-Log -Message "==="
Write-Log -Message "=== ЗУПИНКА СЛУЖБ ==="

# 1. Зупинка Apache
if ($ApacheServiceExists -and $ApacheEnabled) {
    try {
        $apacheProcess = Get-Process "httpd" -ErrorAction SilentlyContinue
        if ($apacheProcess) {
            Write-Log -Message "Зупинка служби Apache..." -Level "INFO"
            Start-Process $Apache -ArgumentList "-k stop" -Wait
            Start-Sleep -Seconds 3
            
            if (Get-Process "httpd" -ErrorAction SilentlyContinue) {
                Write-Log -Message "Примусове завершення Apache..." -Level "INFO"
                Stop-Process -Name "httpd" -Force
                Start-Sleep -Seconds 2
            }
            
            if (-not (Get-Process "httpd" -ErrorAction SilentlyContinue)) {
                Write-Log -Message "Apache успішно зупинено" -Level "SUCCESS"
            } else {
                $errorMsg = "Не вдалося зупинити Apache"
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            }
        }
        else {
            Write-Log -Message "Apache вже зупинений - операція не потрібна" -Level "INFO"
        }
    } catch {
        $errorMsg = "Помилка при зупинці Apache: $($_.Exception.Message)"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
    }
}

# 2. Зупинка exchangAPI
$exchangAPIService = Get-Service -Name $ExchangAPIServiceName -ErrorAction SilentlyContinue
if ($exchangAPIService) {
    $serviceStatus = $exchangAPIService.Status
    if ($serviceStatus -eq 'Running') {
        Write-Log -Message "Зупинка служби $ExchangAPIServiceName..." -Level "INFO"
        Stop-Service -Name $ExchangAPIServiceName -Force
        
        $waitTime = 30
        $startTime = Get-Date
        while ((Get-Service -Name $ExchangAPIServiceName).Status -ne 'Stopped' -and (Get-Date).Subtract($startTime).TotalSeconds -lt $waitTime) {
            Start-Sleep -Seconds 2
        }
        
        if ((Get-Service -Name $ExchangAPIServiceName).Status -eq 'Stopped') {
            Write-Log -Message "Служба $ExchangAPIServiceName успішно зупинена" -Level "SUCCESS"
        } else {
            $errorMsg = "Не вдалося зупинити службу $ExchangAPIServiceName"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    } else {
        Write-Log -Message "Служба $ExchangAPIServiceName вже зупинена" -Level "INFO"
    }
} else {
    $exchangAPIProcess = Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue
    if ($exchangAPIProcess) {
        Write-Log -Message "Зупинка процесу $ExchangAPIProcessName..." -Level "INFO"
        $exchangAPIProcess | Stop-Process -Force
        Start-Sleep -Seconds 2
        
        if (-not (Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Процес $ExchangAPIProcessName успішно зупинено" -Level "SUCCESS"
        } else {
            $errorMsg = "Не вдалося зупинити процес $ExchangAPIProcessName"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    } else {
        Write-Log -Message "Процес $ExchangAPIProcessName не знайдено (не запущений)" -Level "INFO"
    }
}

# 3. Зупинка служби BRAVO
try {
    $bravoService = Get-CimInstance Win32_Service -Filter "Name LIKE '%$BravoServiceName%'" | 
        Select-Object -First 1
    
    if ($bravoService) {
        $BravoServiceName = $bravoService.Name
        $serviceStatus = (Get-Service -Name $BravoServiceName).Status
        
        if ($serviceStatus -eq 'Running') {
            Write-Log -Message "Зупинка служби $BravoServiceName..." -Level "INFO"
            
            # Завершення додаткових процесів
            $processNames = @("Bis")
            foreach ($procName in $processNames) {
                $process = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($process) {
                    Write-Log -Message "Завершення процесу $procName..." -Level "INFO"
                    $process | Stop-Process -Force
                    Start-Sleep -Seconds 1
                }
            }
            
            Stop-Service -Name $BravoServiceName -Force
            
            $timeout = 30
            $serviceStatus = (Get-Service -Name $BravoServiceName).Status
            
            while ($serviceStatus -ne 'Stopped' -and $timeout -gt 0) {
                Start-Sleep -Seconds 1
                $timeout--
                $serviceStatus = (Get-Service -Name $BravoServiceName).Status
            }
            
            if ($serviceStatus -eq 'Stopped') {
                Write-Log -Message "Служба $BravoServiceName успішно зупинена" -Level "SUCCESS"
            } else {
                $errorMsg = "$BravoServiceName не зупинився автоматично"
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            }
        }
        else {
            Write-Log -Message "Служба $BravoServiceName вже зупинена" -Level "INFO"
        }
    } else {
        $errorMsg = "СЕРВІС BRAVO НЕ ЗНАЙДЕНО! Перевірте налаштування"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
    }
} catch {
    $errorMsg = "Помилка при зупинці ${BravoServiceName}: $($_.Exception.Message)"
    Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
    Send-SlackAlert -Message $errorMsg -IsCritical
    $global:criticalErrorOccurred = $true
}

# ===== ПЕРЕВІРКА РОЗМІРІВ ФАЙЛІВ .md =====
Check-MdFileSizes -MODEL_PATH $MODEL_PATH -MAX_MD_FILE_SIZE $MAX_MD_FILE_SIZE

# ===== ОПЕРАЦІЇ ПІСЛЯ ЗУПИНКИ СЕРВІСІВ =====
$bravoStatus = if ($bravoService) { (Get-Service -Name $BravoServiceName).Status } else { 'Unknown' }
if ($bravoStatus -ne "Running") {
    if ($shouldRestore) {
        try {
            Write-Log -Message "==="
            Write-Log -Message "=== РЕСТАВРАЦІЯ МОДЕЛІ ==="
            
            if ($CheckSize) {
                Write-Log -Message "Збереження розмірів файлів перед реставрацією..." -Level "INFO"
                $initialSizes = Get-ChildItem -Path $MODEL_PATH -Recurse -File | 
                    ForEach-Object {
                        [PSCustomObject]@{
                            RelativePath = $_.FullName.Replace($MODEL_PATH, "").TrimStart('\')
                            SizeBytes = $_.Length
                        }
                    }
                
                # Запис без BOM
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                $csvData = $initialSizes | ConvertTo-Csv -NoTypeInformation
                [System.IO.File]::WriteAllLines($SIZES_FILE, $csvData, $utf8NoBom)
                
                Write-Log -Message "Розміри файлів збережено: $SIZES_FILE" -Level "SUCCESS"
            }
            
            # Архівація перед реставрацією
            $arcArgs = $arcCommonParams + @("$ARC_DIR\$ARCH_NAME1", "$MODEL_PATH\*")
            $exitCode = Invoke-CommandWithLog -Command $ARC_PATH -Arguments $arcArgs -Description "Архівація моделі перед реставрацією"
            
            if ($exitCode -ne 0) {
                $errorMsg = "Архівація моделі перед реставрацією не вдалася! Код помилки: $exitCode. Реставрація скасована."
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            } else {
                Write-Log -Message "Архів моделі перед реставрацією створено -> $ARC_DIR\$ARCH_NAME1" -Level "SUCCESS"
                
                # Перевірка контрольних сум після архівації (лише для before)
                $null = Verify-Backup -ArchivePath "$ARC_DIR\$ARCH_NAME1"
                
                # Виконання реставрації через bravocmd.exe (як в еталоні)
                $restoreArgs = @("r", "null", "$ROOT_LIMS\MODEL\lims")
                $exitCode = Invoke-CommandWithLog -Command "$ROOT_LIMS\bravocmd.exe" -Arguments $restoreArgs -Description "Виконання реставрації моделі LIMS"
                
                if ($exitCode -eq 0) {
                    Write-Log -Message "Модель успішно відреставрована" -Level "SUCCESS"
                    
                    # Архівація після реставрації ВИКОНУЄТЬСЯ З УМОВАМИ
                    $restoreRequired = $false
                    $createMarker = $true
                    
                    if ($CheckSize) {
                        Write-Log -Message "Порівняння розмірів файлів..." -Level "INFO"
                        $criticalChanges = Compare-FileSizes -BeforeFile $SIZES_FILE -ModelPath $MODEL_PATH -MinSizeBytes 2048
                        
                        if ($criticalChanges) {
                            Write-Log -Message "УВАГА: Виявлено критичні зміни розмірів файлів!" -Level "WARNING"
                            Write-Log -Message "Відновлення моделі з архіву перед реставрацією..." -Level "INFO"
                            
                            $exitCode = Restore-FromArchive -ArchivePath "$ARC_DIR\$ARCH_NAME1" -Destination $MODEL_PATH -ARC_PATH $ARC_PATH
                            if ($exitCode -eq 0) {
                                Write-Log -Message "Модель успішно відновлена з архіву перед реставрації" -Level "SUCCESS"
                                $restoreRequired = $true
                                $createMarker = $false  # Скасувати маркер
                            }
                        }
                    }
                    
                    # Виконуємо архівацію після реставрації ЛИШЕ якщо не було критичних змін
                    if (-not $restoreRequired) {
                        $arcArgs = $arcCommonParams + @("$ARC_DIR\$ARCH_NAME2", "$MODEL_PATH\*")
                        $exitCode = Invoke-CommandWithLog -Command $ARC_PATH -Arguments $arcArgs -Description "Архівація моделі після реставрації"
                        if ($exitCode -eq 0) {
                            Write-Log -Message "Архів моделі після реставрації створено -> $ARC_DIR\$ARCH_NAME2" -Level "SUCCESS"
                            $null = Verify-Backup -ArchivePath "$ARC_DIR\$ARCH_NAME2"
                        }
                        
                        # Створення маркера ЛИШЕ при успішній реставрації без критичних змін
                        if ($createMarker -and -not $ForceRestore) {
                            Set-Content -Path $MARKER_FILE -Value "Реставрація виконана $NOW"
                            Write-Log -Message "Створено маркерний файл: $MARKER_FILE" -Level "SUCCESS"
                        }
                    } else {
                        Write-Log -Message "Архівація після реставрації ПРОПУЩЕНА через критичні зміни" -Level "WARNING"
                    }
                }
            }
        }
        catch {
            $errorMsg = "Критична помилка під час реставрації: $($_.Exception.Message)"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    }
    
    # Обробка лог-файлів (об'єднаний етап)
    try {
        Write-Log -Message "==="
        # Обробка trace-файлів
        Write-Log -Message "=== ОБРОБКА TRACE-ФАЙЛІВ ===" -Level "INFO"
        $outFiles = Get-ChildItem -Path "$ROOT_LIMS" -Filter "*.out" -ErrorAction SilentlyContinue
        if ($outFiles) {
            foreach ($file in $outFiles) {
                Move-WithSequence -sourcePath $file.FullName -destDir $TRACE_ARCHIV_DIR -SkipIfEmpty
            }
            Write-Log -Message "Оброблено $($outFiles.Count) trace-файлів" -Level "SUCCESS"
        } else {
            Write-Log -Message "[ІНФО] Немає trace-файлів для обробки" -Level "INFO"
        }
        
        # Обробка логів exchangAPI
        Write-Log "==="
        Write-Log -Message "=== ОБРОБКА ЛОГІВ EXCHANGAPI ===" -Level "INFO"
        $exchangAPILogs = Get-ChildItem -Path "$ROOT_LIMS" -Filter "exchangAPI_*.log" -ErrorAction SilentlyContinue
        if ($exchangAPILogs) {
            foreach ($file in $exchangAPILogs) {
                Move-ExchangAPILogs -sourcePath $file.FullName -destDir $EXCHANGAPI_ARCHIV_DIR
            }
        Write-Log -Message "Оброблено $($exchangAPILogs.Count) лог-файлів exchangAPI" -Level "SUCCESS"
            } else {
        Write-Log -Message "[ІНФО] Немає лог-файлів exchangAPI для обробки" -Level "INFO"
        }
		
        # Обробка логів Apache
        if ($ApacheServiceExists -and $ApacheEnabled) {
            Write-Log -Message "=== ОБРОБКА ЛОГІВ APACHE ===" -Level "INFO"
            $apacheLogFiles = Get-ChildItem -Path $APACHE_LOGS_DIR -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.Length -gt 0 }
            
            if ($apacheLogFiles) {
                foreach ($file in $apacheLogFiles) {
                    Move-WithSequence -sourcePath $file.FullName -destDir $BRAVO_WEB_DAILY_DIR -SkipIfEmpty
                }
                Write-Log -Message "Оброблено $($apacheLogFiles.Count) Apache файлів" -Level "SUCCESS"
            } else {
                Write-Log -Message "[ІНФО] Немає Apache файлів для обробки" -Level "INFO"
            }
        }
        
        # Обробка логів WWW
        if ($ApacheServiceExists -and $ApacheEnabled) {
            Write-Log -Message "=== ОБРОБКА ЛОГІВ WWW ===" -Level "INFO"
            $wwwLogFiles = Get-ChildItem -Path $WWW_LOGS_DIR -File -ErrorAction SilentlyContinue | 
                Where-Object { $_.Length -gt 0 }
            
            if ($wwwLogFiles) {
                foreach ($file in $wwwLogFiles) {
                    Move-WithSequence -sourcePath $file.FullName -destDir $BRAVO_WEB_DAILY_DIR -SkipIfEmpty
                }
                Write-Log -Message "Оброблено $($wwwLogFiles.Count) WWW файлів" -Level "SUCCESS"
            } else {
                Write-Log -Message "[ІНФО] Немає WWW файлів для обробки" -Level "INFO"
            }
        }
    }
    catch {
        $errorMsg = "Помилка при обробці лог-файлів: $($_.Exception.Message)"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg
        $global:criticalErrorOccurred = $true
    }
}
else {
    $errorMsg = "Сервіс $($BravoServiceName) все ще працює. Операції з файлами пропущено."
    Write-Log -Message $errorMsg -Level "ERROR"
    Send-SlackAlert -Message $errorMsg
    $global:criticalErrorOccurred = $true
}

# ===== ЗАПУСК СЕРВІСІВ =====
Write-Log -Message "==="
Write-Log -Message "=== ЗАПУСК СЛУЖБ ==="

# 1. Запуск служби BRAVO
try {
    if ($bravoService -and (Get-Service -Name $BravoServiceName).Status -ne 'Running') {
        Write-Log -Message "Запуск служби $BravoServiceName..." -Level "INFO"
        Start-Service -Name $BravoServiceName
        
        $timeout = 60
        $serviceStatus = (Get-Service -Name $BravoServiceName).Status
        
        while ($serviceStatus -ne 'Running' -and $timeout -gt 0) {
            Start-Sleep -Seconds 5
            $timeout -= 5
            $serviceStatus = (Get-Service -Name $BravoServiceName).Status
        }
        
        if ($serviceStatus -eq 'Running') {
            Write-Log -Message "Служба $BravoServiceName успішно запущена" -Level "SUCCESS"
        } else {
            $errorMsg = "$BravoServiceName не запустився автоматично"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    }
} catch {
    $errorMsg = "Помилка при запуску ${BravoServiceName}: $($_.Exception.Message)"
    Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
    Send-SlackAlert -Message $errorMsg -IsCritical
    $global:criticalErrorOccurred = $true
}

# 2. Запуск exchangAPI
if ($exchangAPIService) {
    $serviceStatus = (Get-Service -Name $ExchangAPIServiceName).Status
    if ($serviceStatus -ne 'Running') {
        Write-Log -Message "Запуск служби $ExchangAPIServiceName..." -Level "INFO"
        Start-Service -Name $ExchangAPIServiceName
        
        $waitTime = 30
        $startTime = Get-Date
        while ((Get-Service -Name $ExchangAPIServiceName).Status -ne 'Running' -and (Get-Date).Subtract($startTime).TotalSeconds -lt $waitTime) {
            Start-Sleep -Seconds 2
        }
        
        if ((Get-Service -Name $ExchangAPIServiceName).Status -eq 'Running') {
            Write-Log -Message "Служба $ExchangAPIServiceName успішно запущена" -Level "SUCCESS"
        } else {
            $errorMsg = "$ExchangAPIServiceName не запустився автоматично"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    } else {
        Write-Log -Message "Служба $ExchangAPIServiceName вже запущена" -Level "INFO"
    }
} else {
    if (Test-Path $ExchangAPIExePath) {
        Write-Log -Message "Запуск процесу $ExchangAPIProcessName..." -Level "INFO"
        Start-Process -FilePath $ExchangAPIExePath -WindowStyle Hidden
        
        Start-Sleep -Seconds 3
        if (Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue) {
            Write-Log -Message "Процес $ExchangAPIProcessName успішно запущено" -Level "SUCCESS"
        } else {
            $errorMsg = "Не вдалося запустити процес $ExchangAPIProcessName"
            Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            $global:criticalErrorOccurred = $true
        }
    } else {
        $errorMsg = "Файл $ExchangAPIExePath не знайдено"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg
    }
}

# 3. Запуск Apache (виконується останнім)
if ($ApacheServiceExists -and $ApacheEnabled) {
    try {
        if (-not (Get-Process "httpd" -ErrorAction SilentlyContinue)) {
            Write-Log -Message "Запуск служби Apache..." -Level "INFO"
            Start-Process $Apache -ArgumentList "-D SSL -k start" -Wait
            Start-Sleep -Seconds 3
            
            if (-not (Get-Process "httpd" -ErrorAction SilentlyContinue)) {
                Write-Log -Message "Спроба альтернативного запуску Apache..." -Level "INFO"
                Start-Process $Apache -ArgumentList "-k start" -Wait
                Start-Sleep -Seconds 3
            }
            
            if (Get-Process "httpd" -ErrorAction SilentlyContinue) {
                Write-Log -Message "Служба Apache успішно запущена" -Level "SUCCESS"
            } else {
                $errorMsg = "Apache не запустився"
                Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
                Send-SlackAlert -Message $errorMsg -IsCritical
                $global:criticalErrorOccurred = $true
            }
        }
    } catch {
        $errorMsg = "Помилка при запуску Apache: $($_.Exception.Message)"
        Write-Log -Message "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
    }
}

# ===== ОЧИСТКА СТАРИХ ДАНИХ =====
# Перевіряємо, чи є що очищати
$hasDataToClean = $false

# Перевірка Trace
$traceOldDirs = Get-ChildItem -Path $TRACE_DIR -Directory -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.CreationTime -lt (Get-Date).AddDays(-$ARCHIVE_RETENTION_DAYS) }
$traceOldLogs = Get-ChildItem -Path $LOG_DIR -File -ErrorAction SilentlyContinue | 
    Where-Object { 
        $_.CreationTime -lt (Get-Date).AddDays(-$LOG_RETENTION_DAYS) -and 
        ($_.Name -like "script_log_*.txt" -or 
         $_.Name -like "file_sizes_*.csv" -or 
         $_.Name -like "restore_done_*.marker")
    }

# Перевірка архівів реставрації
$mainArchivePatterns = @("${ArchivePrefix}_before_*.mdz", "${ArchivePrefix}_after_*.mdz")
$mainArchiveFiles = $mainArchivePatterns | ForEach-Object {
    Get-ChildItem -Path $ARC_DIR -Filter $_ -ErrorAction SilentlyContinue
}

if ($mainArchiveFiles -and $mainArchiveFiles.Count -gt 0) {
    $archiveGroups = $mainArchiveFiles | Group-Object { 
        if ($_.Name -match "${ArchivePrefix}_(before|after)_(\d{8}_\d{4})\.mdz") {
            $Matches[2]
        } else {
            $_.CreationTime.ToString("yyyyMMdd_HHmm")
        }
    }
    $sortedGroups = $archiveGroups | Sort-Object Name -Descending
    $groupsToDelete = $sortedGroups | Select-Object -Skip $RESTORE_ARCHIVES_KEEP_COUNT
    $hasDataToClean = $hasDataToClean -or ($groupsToDelete.Count -gt 0)
} else {
    $groupsToDelete = @()
}

# Перевірка логів exchangAPI
$exchangAPIOldLogs = Get-ChildItem -Path $EXCHANGAPI_ARCHIV_DIR -File -ErrorAction SilentlyContinue | 
    Where-Object { 
        $_.CreationTime -lt (Get-Date).AddDays(-$LOG_RETENTION_DAYS) -and 
        $_.Name -like "exchangAPI_*.log"
    }

# Перевірка Br-a-vo.web (якщо Apache встановлений)
if ($ApacheServiceExists -and $ApacheEnabled) {
    $bravoWebOldDirs = Get-ChildItem -Path $BRAVO_WEB_ARCHIV_DIR -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.CreationTime -lt (Get-Date).AddDays(-$ARCHIVE_RETENTION_DAYS) }
    $hasDataToClean = $hasDataToClean -or ($bravoWebOldDirs.Count -gt 0)
}

# Загальна перевірка наявності даних для очищення
$hasDataToClean = $hasDataToClean -or ($traceOldDirs.Count -gt 0) -or ($traceOldLogs.Count -gt 0) -or ($exchangAPIOldLogs.Count -gt 0)

# Якщо є дані для очищення - показуємо заголовок
if ($hasDataToClean) {
    Write-Log -Message "==="
    Write-Log -Message "=== ОЧИСТКА СТАРИХ ДАНИХ ==="
}

# Обробка Trace (тільки якщо є що обробляти)
if ($traceOldDirs.Count -gt 0 -or $traceOldLogs.Count -gt 0) {
    Process-OldData -Path $TRACE_DIR -ArchiveNamePrefix "Trace" -RetentionDays $ARCHIVE_RETENTION_DAYS -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH
}

# Обробка логів Br-a-vo.web (лише якщо служба Apache встановлена і є дані)
if ($ApacheServiceExists -and $ApacheEnabled -and $bravoWebOldDirs.Count -gt 0) {
    Process-OldData -Path $BRAVO_WEB_ARCHIV_DIR -ArchiveNamePrefix "WebLogs" -RetentionDays $ARCHIVE_RETENTION_DAYS -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH
}

# Очистка старих лог-файлів (всіх типів) - тільки якщо є що видаляти
if ($traceOldLogs.Count -gt 0) {
    Remove-OldLogFiles -Path $LOG_DIR -RetentionDays $LOG_RETENTION_DAYS
}

# Видалення старих архівів реставрації - тільки якщо є що видаляти
if ($groupsToDelete.Count -gt 0) {
    Remove-OldRestoreArchives -Path $ARC_DIR -ArchivePrefix $ArchivePrefix -KeepCount $RESTORE_ARCHIVES_KEEP_COUNT
}

# Видалення старих логів exchangAPI - тільки якщо є що видаляти
if ($exchangAPIOldLogs.Count -gt 0) {
    Remove-OldLogFiles -Path $EXCHANGAPI_ARCHIV_DIR -RetentionDays $LOG_RETENTION_DAYS
}

# ===== ЗАПУСК ДОДАТКОВОГО СКРИПТУ ARCHIV_LIMS =====
if ($script:EnableArchivLims) {
    Write-Log -Message "==="
    Write-Log -Message "=== ЗАПУСК СКРИПТУ ARCHIV_LIMS ==="

    try {
        $archivLimsPath = Join-Path -Path $PSScriptRoot -ChildPath "ARCHIV_LIMS.ps1"
        
        if (Test-Path $archivLimsPath) {
            Write-Log -Message "Запуск скрипту ARCHIV_LIMS.ps1..." -Level "INFO"
            
            # Запускаємо скрипт з такими ж параметрами
            $archivParams = @()
            if ($ForceRestore) { $archivParams += "-ForceRestore" }
            if ($DisableSizeCheck) { $archivParams += "-DisableSizeCheck" }
            if ($EnableAllSlack) { $archivParams += "-EnableAllSlack" }
            if ($DisableAllSlack) { $archivParams += "-DisableAllSlack" }
            if ($AutoShutdown -eq "on") { $archivParams += "-AutoShutdown" }
            if ($ArchivLims -eq "on") { $archivParams += "-ArchivLims" }
            
            $archivProcess = Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$archivLimsPath`" $($archivParams -join ' ')" `
                -Wait `
                -PassThru `
                -NoNewWindow
            
            if ($archivProcess.ExitCode -eq 0) {
                Write-Log -Message "Скрипт ARCHIV_LIMS.ps1 успішно виконано" -Level "SUCCESS"
            } else {
                Write-Log -Message "Скрипт ARCHIV_LIMS.ps1 завершено з кодом помилки: $($archivProcess.ExitCode)" -Level "WARNING"
            }
        } else {
            Write-Log -Message "Скрипт ARCHIV_LIMS.ps1 не знайдено за шляхом: $archivLimsPath" -Level "WARNING"
        }
    }
    catch {
        Write-Log -Message "Помилка під час запуску скрипту ARCHIV_LIMS.ps1: $($_.Exception.Message)" -Level "ERROR"
    }
} else {
    # Мінімальне інформаційне повідомлення без заголовків
    Write-Log -Message "Запуск ARCHIV_LIMS: вимкнено" -Level "DEBUG"
}

# ===== ВИКЛИК ФУНКЦІЇ АВТОМАТИЧНОГО ВИМКНЕННЯ =====
if ($script:EnableAutoShutdown) {
    Invoke-AutoShutdown -Timeout $ShutdownTimeout
} else {
    # Мінімальне інформаційне повідомлення без заголовків
    Write-Log -Message "Автоматичне вимкнення: вимкнено" -Level "DEBUG"
}

# Відправляємо фінальний звіт
Send-FinalReport -LOG_FILE $LOG_FILE

# Додаємо інформацію про статус відправки Slack
# if ($script:SlackMode -ne "none") {
    # Видаліть перевірку $slackReportSent, оскільки тепер функція нічого не повертає
#     Write-Log -Message "Фінальний звіт оброблено" -Level "INFO"
# }

# ===== ЗАВЕРШЕННЯ СКРИПТУ =====
$totalTime = (Get-Date) - $global:ScriptStartTime

# ФІНАЛЬНИЙ БЛОК ЗАВЕРШЕННЯ
Write-Log -Message "==="
Write-Log -Message "=== СИСТЕМА ОБСЛУГОВУВАННЯ BRAVOSOFT ЗАВЕРШИЛА РОБОТУ ==="
Write-Log -Message "=== УСТАНОВА: $($global:ObjectName) ==="
Write-Log -Message "=== ЧАС ВИКОНАННЯ: $(Format-Duration $totalTime) ==="
Write-Log -Message "=== СТАТУС: $(if ($global:criticalErrorOccurred) {'З ПОМИЛКАМИ'} else {'УСПІШНО'}) ==="
Write-Log -Message "==="

exit $(if ($global:criticalErrorOccurred) {1} else {0})