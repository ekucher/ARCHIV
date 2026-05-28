# ==============================================================================
# BRAVO.Maintenance.Main.ps1
# Основний сценарій BRAVO MAINTENANCE.
# ==============================================================================

function Invoke-BravoMaintenance {
# ===== ОСНОВНИЙ КОД СКРИПТУ =====

Assert-BravoAdministrator -ScriptName "BRAVO MAINTENANCE"
Assert-BravoPowerShellVersion -Major 5 -Minor 1
Assert-Bravo64BitOperatingSystem
Assert-BravoWindowsVersion

$ApacheEnabled = $false
if ($ApacheServiceExists -and (Test-Path $BRAVO_WEB_DIR)) {
    $Apache = "$BRAVO_WEB_DIR\apache\bin\httpd.exe"
    $ApacheExists = Test-Path $Apache
    $ApacheLogsExist = (Test-Path "$BRAVO_WEB_DIR\apache\logs") -and (Test-Path "$BRAVO_WEB_DIR\www\log")
    $ApacheEnabled = $ApacheExists -and $ApacheLogsExist
}

$scriptPath = if ($global:BravoScriptRoot) { $global:BravoScriptRoot } else { $PSScriptRoot }
if (-not $scriptPath) { $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path }
Assert-BravoArchivFolder -ScriptPath $scriptPath

$ROOT_LIMS = if ($global:ROOT_PATH) { $global:ROOT_PATH } else { Split-Path -Parent $scriptPath }
$archiveRoot = if ($global:archivPath) { $global:archivPath } else { Join-Path $ROOT_LIMS "ARCHIV" }
$ExchangAPIExePath = Join-Path $ROOT_LIMS "exchangAPI.exe"

$MODEL_PATH = Join-Path $ROOT_LIMS "Model"
$LOG_DIR = Join-Path $archiveRoot "LOGS"
$TRACE_DIR = Join-Path $archiveRoot "Trace"
$ARC_DIR = Join-Path $archiveRoot "LIMS"
$maintenanceToolsPath = if ($global:toolsPath) { $global:toolsPath } else { Join-Path $archiveRoot "Tools" }
$ARC_PATH = Join-Path $maintenanceToolsPath "7za.exe"
$EXCHANGAPI_ARCHIV_DIR = Join-Path $archiveRoot "exchangAPI"

if ($ApacheServiceExists -and $ApacheEnabled) {
    $BRAVO_WEB_ARCHIV_DIR = Join-Path $archiveRoot "Br-a-vo.web"
    $APACHE_LOGS_DIR = Join-Path (Join-Path $BRAVO_WEB_DIR "apache") "logs"
    $WWW_LOGS_DIR = Join-Path (Join-Path $BRAVO_WEB_DIR "www") "log"
}

Initialize-BravoDirectory -Path $LOG_DIR -Description "директорію для логів"

$currentDate = Get-Date
$NOW = $currentDate.ToString("yyyyMMdd_HHmm")
$YYYY = $currentDate.Year.ToString("0000")
$MM = $currentDate.Month.ToString("00")
$DD = $currentDate.Day.ToString("00")

$isRestoreDay = ($currentDate.DayOfWeek -eq $RestoreDayOfWeek)
$restoreTimeSpan = [TimeSpan]::Parse($RestoreTime)
$isAfterRestoreTime = ($currentDate.TimeOfDay -ge $restoreTimeSpan)

$MARKER_FILE = "$LOG_DIR\restore_done_$YYYY$MM$DD.marker"

# ========== ВИПРАВЛЕННЯ: ГАРАНТОВАНА РОБОТА KEY -ForceRestore ==========
if ($ForceRestore) {
    $shouldRestore = $true
    $restoreReason = "Примусово (ігнорує розклад та маркер)"
    #Write-Host "✓ Примусова реставрація: АКТИВОВАНО" -ForegroundColor Green
} else {
    $shouldRestore = ($isRestoreDay -and $isAfterRestoreTime -and -not (Test-Path $MARKER_FILE))
    $restoreReason = "$RestoreDayName, після $RestoreTime"
}
$CheckSize = -not $DisableSizeCheck

$ARCH_NAME1 = "${ArchivePrefix}_before_$NOW.mdz"
$ARCH_NAME2 = "${ArchivePrefix}_after_$NOW.mdz"
$global:LOG_FILE = "$LOG_DIR\script_log_$NOW.txt"
$SIZES_FILE = "$LOG_DIR\file_sizes_before_$NOW.csv"
$TRACE_ARCHIV_DIR = "$TRACE_DIR\$YYYY-$MM-$DD"

# ===== ПЕРЕВІРКА НАЯВНОСТІ 7za.exe =====
$sevenZipFound = (Test-Path $ARC_PATH)

# ===== ПОЧАТОК ВИКОНАННЯ =====
$separator = "─" * 92
$slackStatus = switch ($script:SlackMode) {
    "none" { "[ВИМКНЕНО]" }
    "errors_only" { "[ЛИШЕ ПОМИЛКИ]" }
    "all" { "[УСІ ПОВІДОМЛЕННЯ]" }
    default { "[$script:SlackMode]" }
}
$restoreStatus = if ($shouldRestore) { "[УВІМКНЕНО] $restoreReason" } else { "[ВИМКНЕНО]" }
$sizeCheckStatus = if ($CheckSize) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }
$shutdownStatus = if ($script:EnableAutoShutdown) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }
$archivLimsStatus = if ($script:EnableArchivLims) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }

Write-Host $separator -ForegroundColor DarkGray
Write-Host "BRAVO MAINTENANCE v1.2.6" -ForegroundColor Cyan
Write-Host "Час запуску     $($currentDate.ToString('yyyy-MM-dd HH:mm:ss'))      Логування: $LogLevel" -ForegroundColor Gray
Write-Host "Конфігурація    $commonConfigPath" -ForegroundColor Gray
Write-Host "Установа        $($global:ObjectName)" -ForegroundColor Gray
Write-Host "Каталоги        $ROOT_LIMS  →  $ARC_DIR" -ForegroundColor Gray
Write-Host "Сервіси         BRAVO: $BravoServiceName | exchangAPI: $ExchangAPIServiceName" -ForegroundColor Gray
Write-Host "Режими          Реставрація: $restoreStatus" -ForegroundColor Gray
Write-Host "Перевірки       Розміри: $sizeCheckStatus | Архіви: до $BACKUP_CHECK_HOURS год. | Диски: попер. ${DISK_SPACE_WARNING_PERCENT}% / крит. ${DISK_SPACE_CRITICAL_PERCENT}%" -ForegroundColor Gray
Write-Host "Додатково       Slack: $slackStatus | ARCHIV_LIMS: $archivLimsStatus | Вимкнення: $shutdownStatus" -ForegroundColor Gray

Write-BravoLogFileLine -Line $separator
Write-BravoLogFileLine -Line "BRAVO MAINTENANCE v1.2.6"
Write-BravoLogFileLine -Line "Установа: $($global:ObjectName)"
Write-BravoLogFileLine -Line $separator

if ($sevenZipFound) {
    Write-Action -Action "7-Zip" -Result "✓ Знайдено ($ARC_PATH)"
} else {
    Write-Action -Action "7-Zip" -Result "✕ Не знайдено ($ARC_PATH)" -IsError
    $global:CriticalErrorsList.Add("КРИТИЧНА ПОМИЛКА: 7za.exe не знайдено за шляхом: $ARC_PATH")
    $global:criticalErrorOccurred = $true
}

if (-not $sevenZipFound) {
    Send-FinalReport -LOG_FILE $global:LOG_FILE
    exit 1
}

# ===== ПЕРЕВІРКА ВІЛЬНОГО МІСЦЯ НА ДИСКАХ =====
$diskSpaceResult = Test-DiskSpace -CheckHours $DISK_SPACE_CHECK_HOURS -WarningPercent $DISK_SPACE_WARNING_PERCENT -CriticalPercent $DISK_SPACE_CRITICAL_PERCENT -MinFreeGB $DISK_SPACE_MIN_FREE_GB -ExcludeDrives $DISK_EXCLUDE_LIST

$dirsToCreate = @($TRACE_DIR, $ARC_DIR, $TRACE_ARCHIV_DIR, $EXCHANGAPI_ARCHIV_DIR)
if ($ApacheServiceExists -and $ApacheEnabled) {
    $BRAVO_WEB_DAILY_DIR = "$BRAVO_WEB_ARCHIV_DIR\$YYYY-$MM-$DD"
    $dirsToCreate += $BRAVO_WEB_ARCHIV_DIR, $BRAVO_WEB_DAILY_DIR
}

$missingDirs = $dirsToCreate | Where-Object { -not (Test-Path $_) }

if ($missingDirs.Count -gt 0) {
    foreach ($dir in $dirsToCreate) {
        if (-not (Test-Path $dir)) {
            try {
                New-Item -Path $dir -ItemType Directory -Force -ErrorAction Stop | Out-Null
                if ($global:LogLevel -eq "DEBUG") { Write-BravoLogFileLine -Line "Каталог створено: $dir" }
            }
            catch {
                $errorMsg = "Не вдалося створити директорію $dir : $($_.Exception.Message)"
                Write-ErrorLog $errorMsg
                Send-SlackAlert -Message $errorMsg -IsCritical
            }
        }
    }
}

Write-ActionHeader -Header "ЗУПИНКА СЛУЖБ"

if ($ApacheServiceExists -and $ApacheEnabled) {
    try {
        $apacheProcess = Get-Process $ApacheProcessName -ErrorAction SilentlyContinue
        if ($apacheProcess) {
            Start-Process $Apache -ArgumentList "-k stop" -Wait
            Start-Sleep -Seconds 3
            
            if (Get-Process $ApacheProcessName -ErrorAction SilentlyContinue) {
                Stop-Process -Name $ApacheProcessName -Force
                Start-Sleep -Seconds 2
            }
            
            if (-not (Get-Process $ApacheProcessName -ErrorAction SilentlyContinue)) {
                Write-Action -Action "Зупинка Apache..." -Result "✓ Apache зупинено"
            } else {
                Write-Action -Action "Зупинка Apache..." -Result "✕ Не вдалося зупинити Apache" -IsError
                Send-SlackAlert -Message "Не вдалося зупинити Apache" -IsCritical
            }
        } else {
            Write-Action -Action "Зупинка Apache..." -Result "✓ Apache вже зупинено"
        }
    } catch {
        Write-Action -Action "Зупинка Apache..." -Result "✕ Помилка: $($_.Exception.Message)" -IsError
        Send-SlackAlert -Message "Помилка при зупинці Apache" -IsCritical
    }
}

$exchangAPIService = Get-Service -Name $ExchangAPIServiceName -ErrorAction SilentlyContinue
if ($exchangAPIService) {
    if ($exchangAPIService.Status -eq 'Running') {
        Stop-Service -Name $ExchangAPIServiceName -Force -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Action -Action "Зупинка служби exchangAPI..." -Result "✓ Службу exchangAPI зупинено"
    } else {
        Write-Action -Action "Зупинка служби exchangAPI..." -Result "✓ Вже зупинено"
    }
} else {
    $exchangAPIProcess = Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue
    if ($exchangAPIProcess) {
        $exchangAPIProcess | Stop-Process -Force
        Start-Sleep -Seconds 2
        if (-not (Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue)) {
            Write-Action -Action "Зупинка процесу exchangAPI..." -Result "✓ Процес зупинено"
        } else {
            Write-Action -Action "Зупинка процесу exchangAPI..." -Result "✕ Не вдалося зупинити" -IsError
            Send-SlackAlert -Message "Не вдалося зупинити процес exchangAPI" -IsCritical
        }
    } else {
        Write-Action -Action "Перевірка exchangAPI..." -Result "✓ Процес не запущено"
    }
}

try {
    $bravoService = Get-CimInstance Win32_Service -Filter "Name LIKE '%$BravoServiceName%'" | Select-Object -First 1
    
    if ($bravoService) {
        $BravoServiceName = $bravoService.Name
        $bravoStatus = (Get-Service -Name $BravoServiceName -ErrorAction SilentlyContinue).Status
        
        if ($bravoStatus -eq 'Running') {
            $processNames = @("Bis")
            foreach ($procName in $processNames) {
                $process = Get-Process -Name $procName -ErrorAction SilentlyContinue
                if ($process) {
                    $process | Stop-Process -Force
                    Start-Sleep -Seconds 1
                }
            }
            
            Stop-Service -Name $BravoServiceName -Force -WarningAction SilentlyContinue
            Start-Sleep -Seconds 3
            Write-Action -Action "Зупинка служби BRAVO..." -Result "✓ Службу BRAVO зупинено"
        } else {
            Write-Action -Action "Зупинка служби BRAVO..." -Result "✓ Вже зупинено"
        }
    } else {
        Write-Action -Action "Зупинка служби BRAVO..." -Result "! Службу не знайдено"
    }
} catch {
    Write-Action -Action "Зупинка служби BRAVO..." -Result "✕ Помилка: $($_.Exception.Message)" -IsError
    Send-SlackAlert -Message "Помилка при зупинці BRAVO" -IsCritical
}

Write-ActionHeader -Header "ПЕРЕВІРКА РОЗМІРІВ .MD ФАЙЛІВ"
Check-MdFileSizes -MODEL_PATH $MODEL_PATH -MAX_MD_FILE_SIZE $MAX_MD_FILE_SIZE

$bravoStatus = if ($bravoService) { (Get-Service -Name $BravoServiceName -ErrorAction SilentlyContinue).Status } else { 'Unknown' }

# ===== ВИПРАВЛЕННЯ: ПРИМУСОВЕ ВИКОНАННЯ ПРИ -ForceRestore =====
if ($ForceRestore -or ($bravoStatus -ne "Running")) {
    
if ($shouldRestore) {
#    Write-Host "=== РЕСТАВРАЦІЯ МОДЕЛІ ===" -ForegroundColor Cyan
    Write-MaintenanceLog -Message "=== РЕСТАВРАЦІЯ МОДЕЛІ ===" -NoTimestamp
    
    try {
        # Збереження розмірів файлів
        if ($CheckSize) {
            Write-Host "Збереження розмірів файлів..." -NoNewline -ForegroundColor White
            $initialSizes = Get-ChildItem -Path $MODEL_PATH -Recurse -File | 
                ForEach-Object {
                    [PSCustomObject]@{
                        RelativePath = $_.FullName.Replace($MODEL_PATH, "").TrimStart('\')
                        SizeBytes = $_.Length
                    }
                }
            
            $utf8NoBom = New-Object System.Text.UTF8Encoding $false
            $csvData = $initialSizes | ConvertTo-Csv -NoTypeInformation
            [System.IO.File]::WriteAllLines($SIZES_FILE, $csvData, $utf8NoBom)
            
            $padding = 35 - "Збереження розмірів файлів".Length
            if ($padding -lt 1) { $padding = 1 }
            $spaces = " " * $padding
            Write-Host "${spaces}✓ Розміри збережено" -ForegroundColor Green
            
            # Запис тільки в лог без виведення в консоль
            $logMessage = "Збереження розмірів файлів... ✓ Розміри збережено"
            Write-BravoLogFileLine -Line $logMessage
        }
        
        # Архівація перед реставрацією
        $archivePathBefore = Join-Path -Path $ARC_DIR -ChildPath $ARCH_NAME1
        $modelFilesPath = Join-Path -Path $MODEL_PATH -ChildPath "*"
        
        Write-Host "Архівація перед реставрацією..." -NoNewline -ForegroundColor White
        try {
            $archiveCreated = New-VerifiedMaintenanceArchive -ArchivePath $archivePathBefore -SourcePath $modelFilesPath -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH -Description "Архівація перед реставрацією"
            $exitCode = if ($archiveCreated) { 0 } else { 1 }
        }
        catch {
            $exitCode = 1
            Write-ErrorLog "Архівація перед реставрацією: $($_.Exception.Message)"
        }
        
        $padding = 35 - "Архівація перед реставрацією".Length
        if ($padding -lt 1) { $padding = 1 }
        $spaces = " " * $padding
        
        if ($exitCode -eq 0) {
            Write-Host "${spaces}✓ Архівація перед реставрацією виконано успішно" -ForegroundColor Green
            $logMessage = "Архівація перед реставрацією... ✓ Виконано успішно"
            Write-BravoLogFileLine -Line $logMessage
            
            $null = Verify-Backup -ArchivePath $archivePathBefore
            
            # Реставрація моделі LIMS
            Write-Host "Реставрація моделі LIMS..." -NoNewline -ForegroundColor White
            $restoreArgs = @("r", "null", "$ROOT_LIMS\MODEL\lims")
            
            try {
                $null = & "$ROOT_LIMS\bravocmd.exe" $restoreArgs 2>&1
                $exitCode = $LASTEXITCODE
            }
            catch {
                $exitCode = 1
            }
            
            $padding = 35 - "Реставрація моделі LIMS".Length
            if ($padding -lt 1) { $padding = 1 }
            $spaces = " " * $padding
            
            if ($exitCode -eq 0) {
                Write-Host "${spaces}✓ Реставрація моделі LIMS виконано успішно" -ForegroundColor Green
                $logMessage = "Реставрація моделі LIMS... ✓ Виконано успішно"
                Write-BravoLogFileLine -Line $logMessage
                
                $restoreRequired = $false
                $createMarker = $true
                
                # Порівняння розмірів файлів
                if ($CheckSize) {
                    Write-Host "Порівняння розмірів файлів..." -NoNewline -ForegroundColor White
                    $criticalChanges = Compare-FileSizes -BeforeFile $SIZES_FILE -ModelPath $MODEL_PATH -MinSizeBytes 2048
                    
                    $padding = 35 - "Порівняння розмірів файлів".Length
                    if ($padding -lt 1) { $padding = 1 }
                    $spaces = " " * $padding
                    
                    if (-not $criticalChanges) {
                        Write-Host "${spaces}✓ Змін у розмірах файлів після реставрації не виявлено" -ForegroundColor Green
                        $logMessage = "Порівняння розмірів файлів... ✓ Змін не виявлено"
                        Write-BravoLogFileLine -Line $logMessage
                    } else {
                        Write-Host "${spaces}✕ Виявлено критичні зміни! Відновлення з архіву..." -ForegroundColor Red
                        $logMessage = "Порівняння розмірів файлів... ✕ Виявлено критичні зміни"
                        Write-BravoLogFileLine -Line $logMessage
                        
                        $exitCode = Restore-FromArchive -ArchivePath $archivePathBefore -Destination $MODEL_PATH -ARC_PATH $ARC_PATH
                        if ($exitCode -eq 0) {
                            $restoreRequired = $true
                            $createMarker = $false
                        }
                    }
                }
                
                # Архівація після реставрації
                if (-not $restoreRequired) {
                    $archivePathAfter = Join-Path -Path $ARC_DIR -ChildPath $ARCH_NAME2
                    Write-Host "Архівація після реставрації..." -NoNewline -ForegroundColor White
                    try {
                        $archiveCreated = New-VerifiedMaintenanceArchive -ArchivePath $archivePathAfter -SourcePath $modelFilesPath -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH -Description "Архівація після реставрації"
                        $exitCode = if ($archiveCreated) { 0 } else { 1 }
                    }
                    catch {
                        $exitCode = 1
                        Write-ErrorLog "Архівація після реставрації: $($_.Exception.Message)"
                    }
                    
                    $padding = 35 - "Архівація після реставрації".Length
                    if ($padding -lt 1) { $padding = 1 }
                    $spaces = " " * $padding
                    
                    if ($exitCode -eq 0) {
                        Write-Host "${spaces}✓ Архівація після реставрації виконано успішно" -ForegroundColor Green
                        $logMessage = "Архівація після реставрації... ✓ Виконано успішно"
                        Write-BravoLogFileLine -Line $logMessage
                        
                        $null = Verify-Backup -ArchivePath $archivePathAfter
                        
                        if ($createMarker -and -not $ForceRestore) {
                            Set-Content -Path $MARKER_FILE -Value "Реставрація виконана $NOW"
                            $logMessage = "Створено маркер реставрації: $MARKER_FILE"
                            Write-BravoLogFileLine -Line $logMessage
                        }
                    } else {
                        Write-Host "${spaces}✕ Архівація після реставрації завершилась з помилкою" -ForegroundColor Red
                        $logMessage = "Архівація після реставрації... ✕ Помилка, код: $exitCode"
                        Write-BravoLogFileLine -Line $logMessage
                    }
                }
            } else {
                $padding = 35 - "Реставрація моделі LIMS".Length
                if ($padding -lt 1) { $padding = 1 }
                $spaces = " " * $padding
                Write-Host "${spaces}✕ Реставрація моделі LIMS завершилась з помилкою" -ForegroundColor Red
                $logMessage = "Реставрація моделі LIMS... ✕ Помилка, код: $exitCode"
                Write-BravoLogFileLine -Line $logMessage
            }
        } else {
            $padding = 35 - "Архівація перед реставрацією".Length
            if ($padding -lt 1) { $padding = 1 }
            $spaces = " " * $padding
            Write-Host "${spaces}✕ Архівація перед реставрацією завершилась з помилкою" -ForegroundColor Red
            $logMessage = "Архівація перед реставрацією... ✕ Помилка, код: $exitCode"
            Write-BravoLogFileLine -Line $logMessage
        }
    }
    catch {
        Write-ErrorLog "Помилка реставрації: $($_.Exception.Message)"
        Send-SlackAlert -Message "Критична помилка при реставрації" -IsCritical
    }
}
    
    Write-ActionHeader -Header "ОБРОБКА ЛОГІВ"
    
    $outFiles = Get-ChildItem -Path "$ROOT_LIMS" -Filter "*.out" -ErrorAction SilentlyContinue
    if ($outFiles) {
        foreach ($file in $outFiles) {
            Move-WithSequence -sourcePath $file.FullName -destDir $TRACE_ARCHIV_DIR -SkipIfEmpty
        }
        Write-Action -Action "Обробка trace-логів" -Result "✓ Оброблено $($outFiles.Count) trace-логів"
    } else {
        Write-Action -Action "Обробка trace-логів" -Result "✓ Немає trace-логів"
    }
    
    $exchangAPILogs = Get-ChildItem -Path "$ROOT_LIMS" -Filter "exchangAPI_*.log" -ErrorAction SilentlyContinue
    if ($exchangAPILogs) {
        foreach ($file in $exchangAPILogs) {
            Move-ExchangAPILogs -sourcePath $file.FullName -destDir $EXCHANGAPI_ARCHIV_DIR
        }
        $count = $exchangAPILogs.Count
        $word = if ($count -eq 1) { "exchangAPI-лог" } else { "exchangAPI-логів" }
        Write-Action -Action "Обробка exchangAPI-логів" -Result "✓ Оброблено $count $word"
    } else {
        Write-Action -Action "Обробка exchangAPI-логів" -Result "✓ Немає exchangAPI-логів"
    }
    
    if ($ApacheServiceExists -and $ApacheEnabled) {
        $apacheLogFiles = Get-ChildItem -Path $APACHE_LOGS_DIR -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 }
        if ($apacheLogFiles) {
            foreach ($file in $apacheLogFiles) {
                Move-WithSequence -sourcePath $file.FullName -destDir $BRAVO_WEB_DAILY_DIR -SkipIfEmpty
            }
            Write-Action -Action "Обробка Apache-логів" -Result "✓ Оброблено $($apacheLogFiles.Count) Apache-логів"
        } else {
            Write-Action -Action "Обробка Apache-логів" -Result "✓ Немає Apache-логів"
        }
        
        $wwwLogFiles = Get-ChildItem -Path $WWW_LOGS_DIR -File -ErrorAction SilentlyContinue | Where-Object { $_.Length -gt 0 }
        if ($wwwLogFiles) {
            foreach ($file in $wwwLogFiles) {
                Move-WithSequence -sourcePath $file.FullName -destDir $BRAVO_WEB_DAILY_DIR -SkipIfEmpty
            }
            Write-Action -Action "Обробка WWW-логів" -Result "✓ Оброблено $($wwwLogFiles.Count) WWW-логів"
        } else {
            Write-Action -Action "Обробка WWW-логів" -Result "✓ Немає WWW-логів"
        }
    }
}
else {
    Write-ErrorLog "Сервіс BRAVO все ще працює. Для примусової реставрації використайте ключ -ForceRestore"
}

Write-ActionHeader -Header "ЗАПУСК СЛУЖБ"

try {
    if ($bravoService -and (Get-Service -Name $BravoServiceName -ErrorAction SilentlyContinue).Status -ne 'Running') {
        Start-Service -Name $BravoServiceName -WarningAction SilentlyContinue
        Start-Sleep -Seconds 5
        Write-Action -Action "Запуск служби BRAVO..." -Result "✓ Службу BRAVO запущено"
    } else {
        Write-Action -Action "Запуск служби BRAVO..." -Result "✓ Вже запущено"
    }
} catch {
    Write-Action -Action "Запуск служби BRAVO..." -Result "✕ Помилка: $($_.Exception.Message)" -IsError
}

if ($exchangAPIService) {
    if ((Get-Service -Name $ExchangAPIServiceName -ErrorAction SilentlyContinue).Status -ne 'Running') {
        Start-Service -Name $ExchangAPIServiceName -WarningAction SilentlyContinue
        Start-Sleep -Seconds 3
        Write-Action -Action "Запуск служби exchangAPI..." -Result "✓ Службу exchangAPI запущено"
    } else {
        Write-Action -Action "Запуск служби exchangAPI..." -Result "✓ Вже запущено"
    }
} else {
    if (Test-Path $ExchangAPIExePath) {
        Start-Process -FilePath $ExchangAPIExePath -WindowStyle Hidden
        Start-Sleep -Seconds 3
        if (Get-Process -Name $ExchangAPIProcessName -ErrorAction SilentlyContinue) {
            Write-Action -Action "Запуск процесу exchangAPI..." -Result "✓ Процес запущено"
        } else {
            Write-Action -Action "Запуск процесу exchangAPI..." -Result "✕ Не вдалося запустити" -IsError
            Send-SlackAlert -Message "Не вдалося запустити exchangAPI" -IsCritical
        }
    } else {
        Write-Action -Action "Запуск exchangAPI..." -Result "✕ Файл не знайдено" -IsError
    }
}

if ($ApacheServiceExists -and $ApacheEnabled) {
    try {
        if (-not (Get-Process $ApacheProcessName -ErrorAction SilentlyContinue)) {
            Start-Process $Apache -ArgumentList "-D SSL -k start" -Wait
            Start-Sleep -Seconds 3
            
            if (-not (Get-Process $ApacheProcessName -ErrorAction SilentlyContinue)) {
                Start-Process $Apache -ArgumentList "-k start" -Wait
                Start-Sleep -Seconds 3
            }
            
            if (Get-Process $ApacheProcessName -ErrorAction SilentlyContinue) {
                Write-Action -Action "Запуск Apache..." -Result "✓ Apache запущено"
            } else {
                Write-Action -Action "Запуск Apache..." -Result "✕ Не запустився" -IsError
                Send-SlackAlert -Message "Apache не запустився" -IsCritical
            }
        } else {
            Write-Action -Action "Запуск Apache..." -Result "✓ Вже запущено"
        }
    } catch {
        Write-Action -Action "Запуск Apache..." -Result "✕ Помилка: $($_.Exception.Message)" -IsError
    }
}

$hasDataToClean = $false

$traceOldDirs = Get-ChildItem -Path $TRACE_DIR -Directory -ErrorAction SilentlyContinue | 
    Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.CreationTime -lt (Get-Date).AddDays(-$ARCHIVE_RETENTION_DAYS) }
$traceOldLogs = Get-ChildItem -Path $LOG_DIR -File -ErrorAction SilentlyContinue | 
    Where-Object { 
        $_.CreationTime -lt (Get-Date).AddDays(-$LOG_RETENTION_DAYS) -and 
        ($_.Name -like "script_log_*.txt" -or $_.Name -like "file_sizes_*.csv" -or $_.Name -like "restore_done_*.marker" -or
         $_.Name -like "disk_space_history_*.csv")
    }

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

$exchangAPIOldLogs = Get-ChildItem -Path $EXCHANGAPI_ARCHIV_DIR -File -ErrorAction SilentlyContinue | 
    Where-Object { $_.CreationTime -lt (Get-Date).AddDays(-$LOG_RETENTION_DAYS) -and $_.Name -like "exchangAPI_*.log" }

if ($ApacheServiceExists -and $ApacheEnabled) {
    $bravoWebOldDirs = Get-ChildItem -Path $BRAVO_WEB_ARCHIV_DIR -Directory -ErrorAction SilentlyContinue | 
        Where-Object { $_.Name -match '^\d{4}-\d{2}-\d{2}$' -and $_.CreationTime -lt (Get-Date).AddDays(-$ARCHIVE_RETENTION_DAYS) }
    $hasDataToClean = $hasDataToClean -or ($bravoWebOldDirs.Count -gt 0)
}

$hasDataToClean = $hasDataToClean -or ($traceOldDirs.Count -gt 0) -or ($traceOldLogs.Count -gt 0) -or ($exchangAPIOldLogs.Count -gt 0)

if ($hasDataToClean) {
    Write-ActionHeader -Header "ОЧИСТКА СТАРИХ ДАНИХ"
    
    if ($traceOldDirs.Count -gt 0 -or $traceOldLogs.Count -gt 0) {
        Process-OldData -Path $TRACE_DIR -ArchiveNamePrefix "Trace" -RetentionDays $ARCHIVE_RETENTION_DAYS -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH
    }
    
    if ($ApacheServiceExists -and $ApacheEnabled -and $bravoWebOldDirs.Count -gt 0) {
        Process-OldData -Path $BRAVO_WEB_ARCHIV_DIR -ArchiveNamePrefix "WebLogs" -RetentionDays $ARCHIVE_RETENTION_DAYS -arcCommonParams $arcCommonParams -ARC_PATH $ARC_PATH
    }
    
    if ($traceOldLogs.Count -gt 0) {
        Remove-OldLogFiles -Path $LOG_DIR -RetentionDays $LOG_RETENTION_DAYS
    }
    
    if ($groupsToDelete.Count -gt 0) {
        Remove-OldRestoreArchives -Path $ARC_DIR -ArchivePrefix $ArchivePrefix -KeepCount $RESTORE_ARCHIVES_KEEP_COUNT
    }
    
    if ($exchangAPIOldLogs.Count -gt 0) {
        Remove-OldLogFiles -Path $EXCHANGAPI_ARCHIV_DIR -RetentionDays $LOG_RETENTION_DAYS
    }
}

$backupCheckResult = Test-BackupIntegrity -MaxHoursOld $BACKUP_CHECK_HOURS -RootPath $ROOT_LIMS

if ($script:EnableArchivLims) {
    Write-ActionHeader -Header "ЗАПУСК ARCHIV_LIMS"
    
    try {
        $archivLimsPath = Join-Path -Path $scriptPath -ChildPath $ArchivLimsPath
        
        if (Test-Path $archivLimsPath) {
            $archivParams = @()
            
            $archivProcess = Start-Process -FilePath "powershell.exe" `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$archivLimsPath`" $($archivParams -join ' ')" `
                -Wait -PassThru -NoNewWindow
            
            if ($archivProcess.ExitCode -eq 0) {
                Write-Action -Action "Виконання ARCHIV_LIMS" -Result "✓ Скрипт виконано успішно"
            } else {
                Write-Action -Action "Виконання ARCHIV_LIMS" -Result "✕ Код помилки: $($archivProcess.ExitCode)" -IsError
            }
        } else {
            Write-Action -Action "Пошук ARCHIV_LIMS" -Result "✕ Скрипт не знайдено" -IsError
        }
    }
    catch {
        Write-Action -Action "Виконання ARCHIV_LIMS" -Result "✕ Помилка: $($_.Exception.Message)" -IsError
    }
} else {
    try {
        Write-BravoLogFileLine -Line "Запуск ARCHIV_LIMS: вимкнено"
    } catch { }
}

if ($script:EnableAutoShutdown) {
    Invoke-AutoShutdown -Timeout $ShutdownTimeout
} else {
    try {
        Write-BravoLogFileLine -Line "Автоматичне вимкнення: вимкнено"
    } catch { }
}

Send-FinalReport -LOG_FILE $global:LOG_FILE

$totalTime = (Get-Date) - $global:ScriptStartTime

Write-Host $separator -ForegroundColor DarkGray
Write-Host "ПІДСУМОК" -ForegroundColor Cyan
Write-Host "Установа        $($global:ObjectName)" -ForegroundColor Gray
Write-Host "Лог             $global:LOG_FILE" -ForegroundColor Gray

if ($global:criticalErrorOccurred) {
    Write-Host "✕ Завершено з помилками   $(Format-Duration $totalTime)" -ForegroundColor Red
} else {
    Write-Host "✓ Готово   $(Format-Duration $totalTime)" -ForegroundColor Green
}
Write-Host $separator -ForegroundColor DarkGray

Write-BravoLogFileLine -Line $separator
Write-BravoLogFileLine -Line "ПІДСУМОК"
Write-BravoLogFileLine -Line "Установа: $($global:ObjectName)"
Write-BravoLogFileLine -Line "Час виконання: $(Format-Duration $totalTime)"
if ($global:criticalErrorOccurred) {
    Write-BravoLogFileLine -Line "Статус: З ПОМИЛКАМИ"
} else {
    Write-BravoLogFileLine -Line "Статус: УСПІШНО"
}
Write-BravoLogFileLine -Line $separator

$isInteractive = [Environment]::UserInteractive
$isPowerShellISE = $Host.Name -like "*ISE*"
$isConsole = $Host.Name -like "*ConsoleHost*"

if (-not $global:BravoScheduledTaskRun -and $isInteractive -and $isConsole -and -not $isPowerShellISE) {
    Write-Host ""
    Write-Host "Натисніть Enter для закриття..." -ForegroundColor Yellow
    Read-Host
}

exit $(if ($global:criticalErrorOccurred) {1} else {0})
}
