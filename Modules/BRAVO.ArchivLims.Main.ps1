# ==============================================================================
# BRAVO.ArchivLims.Main.ps1
# Автоматично винесені функції з BRAVO_ARCHIV_LIMS.ps1
# ==============================================================================

function Initialize-SecureCredentials {
    param([switch]$ForceRecreate)
    
    $networkTarget = $global:credentialTargets.Network
    $sftpTarget = $global:credentialTargets.SFTP
    $archiveTarget = $global:credentialTargets.Archive
    
    Write-Log "=== НАЛАШТУВАННЯ ОБЛІКОВИХ ДАНИХ ===" -Level "INFO"
    
    Ensure-WindowsCredential `
        -Target $networkTarget `
        -PromptTitle "Введіть облікові дані для мережевого доступу:" `
        -PromptDetails "Мережевий шлях: $($global:networkCopyConfig.NetworkPath)" `
        -DefaultUsername $global:networkCopyConfig.Username `
        -ForceRecreate:$ForceRecreate | Out-Null
    
    # Налаштування SFTP облікових даних
    if ($global:sftpConfig.Enabled) {
        Ensure-WindowsCredential `
            -Target $sftpTarget `
            -PromptTitle "Введіть облікові дані для SFTP:" `
            -PromptDetails "SFTP сервер: $($global:sftpConfig.Server):$($global:sftpConfig.Port)" `
            -DefaultUsername $global:sftpConfig.Username `
            -ForceRecreate:$ForceRecreate | Out-Null
    }

    if ($global:enableArchivePassword) {
        Ensure-WindowsCredential `
            -Target $archiveTarget `
            -PromptTitle "Введіть пароль для захищених архівів:" `
            -PromptDetails "Цей пароль буде використовуватись для створення архівів 7-Zip." `
            -DefaultUsername "ARCHIVE_PASSWORD" `
            -ForceRecreate:$ForceRecreate | Out-Null
    }
    
    Write-Log "Налаштування облікових даних завершено" -Level "SUCCESS"
}

function Ensure-RequiredCredentials {
    $allCredentialsReady = $true

    if ($global:secureMode -and ($enableNetworkCopy -or $enableSync.BAZA_Network)) {
        $networkReady = Ensure-WindowsCredential `
            -Target $global:credentialTargets.Network `
            -PromptTitle "Введіть облікові дані для мережевого доступу:" `
            -PromptDetails "Мережевий шлях: $($global:networkCopyConfig.NetworkPath)" `
            -DefaultUsername $global:networkCopyConfig.Username

        $allCredentialsReady = $allCredentialsReady -and $networkReady
    }

    if ($global:secureMode -and $global:sftpConfig.Enabled) {
        $sftpReady = Ensure-WindowsCredential `
            -Target $global:credentialTargets.SFTP `
            -PromptTitle "Введіть облікові дані для SFTP:" `
            -PromptDetails "SFTP сервер: $($global:sftpConfig.Server):$($global:sftpConfig.Port)" `
            -DefaultUsername $global:sftpConfig.Username

        $allCredentialsReady = $allCredentialsReady -and $sftpReady
    }

    if ($global:secureMode -and $global:enableArchivePassword) {
        $archivePasswordReady = Ensure-WindowsCredential `
            -Target $global:credentialTargets.Archive `
            -PromptTitle "Введіть пароль для захищених архівів:" `
            -PromptDetails "Цей пароль буде використовуватись для створення архівів 7-Zip." `
            -DefaultUsername "ARCHIVE_PASSWORD"

        $allCredentialsReady = $allCredentialsReady -and $archivePasswordReady
    }

    return $allCredentialsReady
}

function Main {
    $scriptStartTime = Get-Date
    $now = Get-Date -Format "yyyyMMdd_HHmm"
    $global:logFile = "$logPath\ARCHIV_LIMS_$now.log"
    
    if ($global:logRetentionDays -and $global:logRetentionDays -gt 0) {
        Clear-OldLogs -LogPath $logPath -RetentionDays $global:logRetentionDays
    }
    
    if ($SetupCredentials) {
        Write-Log "=== НАЛАШТУВАННЯ ОБЛІКОВИХ ДАНИХ ===" -Level "INFO"
        Initialize-SecureCredentials -ForceRecreate:$ForceRecreate
        Write-Log "Налаштування завершено. Запустіть скрипт без параметрів." -Level "SUCCESS"
        
        if (-not $global:BravoScheduledTaskRun) {
            Write-Host "`nНатисніть Enter для закриття..."
            Read-Host
        }
        return
    }
    
    Write-Log "====================================================================================================" -Level "INFO"
    Write-Log "=== ПОЧАТОК РОБОТИ СКРИПТА ARCHIV_LIMS v.$ScriptVersion ===" -Level "INFO"
    Write-Log ("Файл конфiгурацiї: " + $configPath) -Level "INFO"
    Write-Log "====================================================================================================" -Level "INFO"
    
    if ($global:secureMode) {
        Write-Log "Облікові дані зберігаються в Windows Credential Manager" -Level "INFO"
        Write-Log "Підключення до мережевого диска буде виконано автоматично" -Level "INFO"
    }

    if (-not (Ensure-RequiredCredentials)) {
        Write-Host "[!!] Не всі облікові дані доступні. Роботу скрипта зупинено." -ForegroundColor Red
        Write-Log "Не всі облікові дані доступні. Роботу скрипта зупинено." -Level "ERROR"
        return
    }
    
    if (-not $arcPath) {
        Write-Host "КРИТИЧНА ПОМИЛКА: 7-Zip не знайдено!" -ForegroundColor Red
        Write-Log "КРИТИЧНА ПОМИЛКА: 7-Zip не знайдено!" -Level "ERROR"
        return
    }
    
    Test-Compatibility | Out-Null
    
    # =============================================
    # ВИВЕДЕННЯ ОПЦІЙ СКРИПТА
    # =============================================
    
    $securityMode = if ($global:secureMode) { "Диспетчер облікових даних Windows" } else { "Стандартний (небезпечний)" }
    $securityColor = if ($global:secureMode) { "Green" } else { "Red" }
    $rotationStatus = if ($enableArchiveDeletion) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }
    $archivePasswordStatus = if ($global:enableArchivePassword) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }
    $networkStatus = if ($enableNetworkCopy) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }
    $networkColor = if ($enableNetworkCopy) { "Green" } else { "Red" }
    $sftpStatus = if ($global:sftpConfig.Enabled) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }
    $sftpColor = if ($global:sftpConfig.Enabled) { "Green" } else { "Red" }
    $syncLocalStatus = if ($enableSync.BAZA_Local) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }
    $syncNetworkStatus = if ($enableSync.BAZA_Network) { "[УВІМКНЕНО]" } else { "[ВИМКНЕНО]" }

    Write-SectionHeader "ARCHIV_LIMS v.$ScriptVersion"
    Write-Host "Час запуску     $($scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss'))      Логування: $LogLevel ($logRetentionDays дн.)" -ForegroundColor Gray
    Write-Host "Конфігурація    $configPath" -ForegroundColor Gray
    Write-Host "Каталоги        $rootPath  →  $archivPath" -ForegroundColor Gray
    Write-Host "Захист          $securityMode | Пароль архівів: $archivePasswordStatus" -ForegroundColor Gray
    Write-Host "Архівація       7-Zip + SHA512" -ForegroundColor Gray
    Write-Host "Зберігання      Ротація: $rotationStatus | Версій: $archiveVersions" -ForegroundColor Gray
    Write-Host "Копії           Мережа: $networkStatus | SFTP: $sftpStatus" -ForegroundColor Gray
    Write-Host "BAZA            Локально: $syncLocalStatus | Мережа: $syncNetworkStatus" -ForegroundColor Gray
    
    Write-Log "=== ОПЦIЇ СКРИПТА ===" -Level "INFO"
    Write-Log ("Версiя: " + $ScriptVersion + " вiд " + $ScriptDate) -Level "INFO"
    Write-Log ("Час початку: " + $scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss')) -Level "INFO"
    Write-Log ("Кореневий каталог: " + $rootPath) -Level "INFO"
    Write-Log ("Каталог архiвiв: " + $archivPath) -Level "INFO"
    Write-Log ("Режим логування: " + $LogLevel) -Level "INFO"
    Write-Log ("Зберігання логів: " + $logRetentionDays + " днiв") -Level "INFO"
    Write-Log ("Режим безпеки: Windows Credential Manager") -Level "INFO"
    if ($enableArchiveDeletion) { Write-Log "Видалення старих архiвiв: УВІМКНЕНО" -Level "INFO" }
    if ($enableNetworkCopy) { Write-Log "Копiювання в мережу: УВІМКНЕНО" -Level "INFO" }
    if ($global:sftpConfig.Enabled) { Write-Log "SFTP завантаження: УВІМКНЕНО (сервер: $($global:sftpConfig.Server))" -Level "INFO" }
    Write-Log "====================================================================================================" -Level "INFO"
    
# ========================
# 1. АРХІВАЦІЯ ТА ХЕШІ
# ========================
Write-SectionHeader "АРХІВАЦІЯ"
Write-Log "====================================================================================================" -Level "INFO"
Write-Log "[ARC] АРХІВАЦІЯ" -Level "INFO"
Write-Log "====================================================================================================" -Level "INFO"

$archives = @()
if ($componentsToArchive.MODEL) { 
    $archives += @{Name = "$($archivePrefix)_$($now).mdz"; Source = $sourcePaths.Model; Destination = $archiveDirs.Model; Type = "MODEL"; DisplayName = "MODEL"}
}
if ($componentsToArchive.BLOG) { 
    $archives += @{Name = "$($archivePrefix)_blog_$($now).mdz"; Source = $sourcePaths.Blog; Destination = $archiveDirs.Blog; Type = "BLOG"; DisplayName = "BLOG"}
}
if ($componentsToArchive.BRAVOEXCH) { 
    $archives += @{Name = "$($archivePrefix)_bravoexch_$($now).mdz"; Source = $sourcePaths.BravoExch; Destination = $archiveDirs.BravoExch; Type = "BRAVOEXCH"; DisplayName = "BRAVOEXCH"}
}

$results = @{}
$totalArchives = $archives.Count
$currentArchive = 0
$successfulArchives = 0

foreach ($archive in $archives) {
    $currentArchive++
    $sourceDir = $archive.Source.TrimEnd('*')
    
    $sourceSizeMB = 0
    if (Test-Path $sourceDir) {
        $sourceSizeBytes = (Get-ChildItem -Path $sourceDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $sourceSizeMB = [math]::Round($sourceSizeBytes / 1MB, 1)
    }
    $sourceSizeStr = Format-SizeMB -SizeMB $sourceSizeMB
    
    if (-not (Test-Path $sourceDir)) {
        $displayLabel = Format-ConsoleText -Text "[$($archive.DisplayName)]" -Width 11
        Write-Host " ✘ [$currentArchive/$totalArchives] $displayLabel Джерело не знайдено" -ForegroundColor Red
        Write-Log "  [!] $($archive.Type): джерело не знайдено - пропущено" -Level "WARNING"
        $results[$archive.Type] = @{ArchiveSuccess = $false; HashSuccess = $false; Skipped = $true}
        continue
    }
    
    $success = New-Archive -SourcePath $archive.Source -ArchivePath $archive.Destination -ArchiveName $archive.Name -ArcPath $arcPath -ArcParams $archiveParams
    
    if ($success) {
        $archivePath = Join-Path $archive.Destination $archive.Name
        
        $archiveSizeBytes = (Get-Item $archivePath -ErrorAction SilentlyContinue).Length
        $archiveSizeMB = [math]::Round($archiveSizeBytes / 1MB, 1)
        $archiveSizeStr = Format-SizeMB -SizeMB $archiveSizeMB
        
        $hashPath = "$archivePath.sha512"
        $hashSuccess = New-SHA512Hash -FilePath $archivePath -HashFilePath $hashPath
        
        $results[$archive.Type] = @{
            ArchivePath = $archivePath
            HashPath = $hashPath
            ArchiveSuccess = $success
            HashSuccess = $hashSuccess
            Skipped = $false
        }
        
        if ($success -and $hashSuccess) {
            $successfulArchives++
            Write-CompactResult -Icon "✓" -Label "[$currentArchive/$totalArchives] $($archive.DisplayName)" -Detail "$sourceSizeStr → $archiveSizeStr" -Status $archive.Name -Color "Green"
        } else {
            Write-CompactResult -Icon "✕" -Label "[$currentArchive/$totalArchives] $($archive.DisplayName)" -Detail "$sourceSizeStr → $archiveSizeStr" -Status "ПОМИЛКА" -Color "Red"
        }
        
        Write-Log "  [OK] $($archive.Type.PadRight(10)) $sourceSizeStr -> $($archive.Name) ($archiveSizeStr)" -Level "SUCCESS"
        Write-Log "  [HASH] $($archive.Type.PadRight(10)) -> $($archive.Name).sha512" -Level "SUCCESS"
    } else {
        $results[$archive.Type] = @{ArchiveSuccess = $false; HashSuccess = $false; Skipped = $false}
        Write-CompactResult -Icon "✕" -Label "[$currentArchive/$totalArchives] $($archive.DisplayName)" -Detail $archive.Name -Status "ПОМИЛКА АРХІВАЦІЇ" -Color "Red"
        Write-Log "  [!!] $($archive.Type): помилка архівації" -Level "ERROR"
    }
}

Write-Host ""
$hashSuccessInArchiveSection = 0
foreach ($key in $results.Keys) {
    if (-not $results[$key].Skipped -and $results[$key].HashSuccess) {
        $hashSuccessInArchiveSection++
    }
}
Write-Host "✓ Архіви: $successfulArchives/$totalArchives | Контрольні суми: $hashSuccessInArchiveSection/$totalArchives" -ForegroundColor Green
Write-Log "[OK] Успішно заархівовано сервісів: $successfulArchives з $totalArchives." -Level "SUCCESS"
Write-Log "====================================================================================================" -Level "INFO"
    
# ========================
# 2. СИНХРОНІЗАЦІЯ BAZA (локальна та мережева)
# ========================
$syncLocalSuccess = $true
$syncNetworkSuccess = $true

if ($enableSync.BAZA_Local -or $enableSync.BAZA_Network) {
    Write-SectionHeader "СИНХРОНІЗАЦІЯ BAZA"
    
    Write-Log "====================================================================================================" -Level "INFO"
    Write-Log "[SYN] СИНХРОНІЗАЦІЯ BAZA" -Level "INFO"
    Write-Log "====================================================================================================" -Level "INFO"
    
    $sourcePath = $bazaPaths.Source
    
    if (-not (Test-Path $sourcePath)) {
        Write-Host "[!!] Джерело не знайдено: $sourcePath" -ForegroundColor Red
        Write-Log "[!!] Джерело не знайдено: $sourcePath" -Level "ERROR"
        $syncLocalSuccess = $false
        $syncNetworkSuccess = $false
    } else {
        $files = Get-ChildItem -Path $sourcePath -Recurse -File -ErrorAction SilentlyContinue
        $fileCount = $files.Count
        $totalSizeBytes = ($files | Measure-Object Length -Sum).Sum
        $totalSizeMB = [math]::Round($totalSizeBytes / 1MB, 1)
        $totalSizeStr = Format-SizeMB -SizeMB $totalSizeMB -Width 0
        
        Write-Host "Файли           $fileCount | Розмір $totalSizeStr" -ForegroundColor Gray
        
        if ($enableSync.BAZA_Local) {
            $destPath = $bazaPaths.Destination
            $localStatus = "Без змін"
            $localColor = "Green"
            Write-Log "[>>] Локальна синхронізація BAZA..." -Level "INFO"
            
            $syncLocalSuccess = Sync-Folders -SourcePath $sourcePath -DestinationPath $destPath -SyncType "LOCAL"
            
            if (-not $syncLocalSuccess) {
                $localStatus = "ПОМИЛКА"
                $localColor = "Red"
            }
            
            $syncLine = Format-ConsoleText -Text "$sourcePath -> $destPath" -Width 62
            Write-Host " ✔ [ЛОКАЛЬНО] $syncLine | $localStatus" -ForegroundColor $localColor
            Write-Log "[DIR] $sourcePath -> $destPath" -Level "SUCCESS"
        }
        
        if ($enableSync.BAZA_Network) {
            $networkDestPath = $bazaPaths.Destination_Network
            $networkStatus = "Без змін"
            $networkColor = "Green"
            Write-Log "[>>] Мережева синхронізація BAZA..." -Level "INFO"
            
            $syncNetworkSuccess = Sync-Folders -SourcePath $sourcePath -DestinationPath $networkDestPath -SyncType "NETWORK"
            
            if (-not $syncNetworkSuccess) {
                $networkStatus = "ПОМИЛКА"
                $networkColor = "Red"
            }
            
            $syncLine = Format-ConsoleText -Text "$sourcePath -> $networkDestPath" -Width 62
            Write-Host " ✔ [МЕРЕЖА]   $syncLine | $networkStatus" -ForegroundColor $networkColor
            Write-Log "[DIR] $sourcePath -> $networkDestPath" -Level "SUCCESS"
        }
        
        Write-Host ""
        
        if ($syncLocalSuccess -and $syncNetworkSuccess) {
            Write-Host "✓ BAZA синхронізовано" -ForegroundColor Green
            Write-Log "[OK] Синхронізацію успішно завершено (оновлень не виявлено)." -Level "SUCCESS"
        } elseif ($syncLocalSuccess -or $syncNetworkSuccess) {
            Write-Host "[!] Синхронізацію завершено з частковими помилками." -ForegroundColor Yellow
            Write-Log "[!] Синхронізацію завершено з частковими помилками." -Level "WARNING"
        } else {
            Write-Host "[!!] Синхронізацію завершено з помилками." -ForegroundColor Red
            Write-Log "[!!] Синхронізацію завершено з помилками." -Level "ERROR"
        }
    }
    
    Write-Log "====================================================================================================" -Level "INFO"
}
    
# ========================
# 3. МЕРЕЖЕВІ ОПЕРАЦІЇ (копіювання архівів)
# ========================
$copySuccess = 0
$copyTotal = 0

if ($enableNetworkCopy) {
    Write-SectionHeader "КОПІЮВАННЯ В МЕРЕЖУ"
    
    Write-Log "====================================================================================================" -Level "INFO"
    Write-Log "[NET] КОПІЮВАННЯ В МЕРЕЖУ" -Level "INFO"
    Write-Log "====================================================================================================" -Level "INFO"
    
    $connected = Connect-NetworkDrive
    if ($connected) {
        $driveInfo = Get-PSDrive -Name "Z" -ErrorAction SilentlyContinue
        $freeSpaceGB = if ($driveInfo) { [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F2}", ($driveInfo.Free / 1GB)) } else { "N/A" }
        Write-Host "Вільно          $freeSpaceGB GB" -ForegroundColor Gray
        
        $successfulPackages = 0
        
        foreach ($archiveType in $results.Keys) {
            if ($results[$archiveType].ArchiveSuccess -and $results[$archiveType].HashSuccess) {
                $targetFolder = switch ($archiveType) {
                    "BLOG"      { "BLOG" }
                    "BRAVOEXCH" { "BRAVOEXCH" }
                    default     { "MODEL" }
                }
                
                $archivePath = $results[$archiveType].ArchivePath
                $archiveName = Split-Path $archivePath -Leaf
                $archiveSizeBytes = (Get-Item $archivePath -ErrorAction SilentlyContinue).Length
                $archiveSizeMB = [math]::Round($archiveSizeBytes / 1MB, 1)
                $archiveSizeStr = Format-SizeMB -SizeMB $archiveSizeMB
                
                $archiveCopySuccess = Copy-ToNetworkDrive -SourcePath $archivePath -DestinationFolder $targetFolder
                if ($archiveCopySuccess) { $copySuccess++ }
                
                $hashPath = $results[$archiveType].HashPath
                $hashCopySuccess = Copy-ToNetworkDrive -SourcePath $hashPath -DestinationFolder $targetFolder
                if ($hashCopySuccess) { $copySuccess++ }
                
                if ($archiveCopySuccess -and $hashCopySuccess) {
                    $successfulPackages++
                    $displayName = switch ($archiveType) {
                        "BLOG"      { "BLOG" }
                        "BRAVOEXCH" { "BRAVOEXCH" }
                        default     { "MODEL" }
                    }
                    
                    Write-CompactResult -Icon "✓" -Label $displayName -Detail $archiveSizeStr -Status "скопійовано" -Color "Green"
                } else {
                    $displayName = switch ($archiveType) {
                        "BLOG"      { "BLOG" }
                        "BRAVOEXCH" { "BRAVOEXCH" }
                        default     { "MODEL" }
                    }
                    Write-CompactResult -Icon "✕" -Label $displayName -Detail $archiveSizeStr -Status "ПОМИЛКА" -Color "Red"
                }
            }
        }
        
        Disconnect-NetworkDrive | Out-Null
        
        Write-Host ""
        $totalFiles = $copySuccess
        if ($successfulPackages -gt 0) {
            $packageWord = Get-PackageWord -Count $successfulPackages
            $fileWord = Get-FileWord -Count $totalFiles
            Write-Host "✓ Мережа: $successfulPackages $packageWord / $totalFiles $fileWord" -ForegroundColor Green
            Write-Log "[OK] Разом скопійовано: $successfulPackages $packageWord даних ($totalFiles $fileWord)." -Level "SUCCESS"
        } else {
            Write-Host "[!!] Не вдалося скопіювати жодного комплекту даних." -ForegroundColor Red
            Write-Log "[!!] Не вдалося скопіювати жодного комплекту даних." -Level "ERROR"
        }
    } else {
        Write-Host "[!!] Не вдалося підключити мережевий диск" -ForegroundColor Red
        Write-Log "[!!] Не вдалося підключити мережевий диск" -Level "ERROR"
    }
    Write-Log "====================================================================================================" -Level "INFO"
}

# ========================
# 4. SFTP ЗАВАНТАЖЕННЯ
# ========================
$sftpSuccessCount = 0
$sftpTotalCount = 0
$sftpSuccess = -not $global:sftpConfig.Enabled
$sftpStatusText = "Вимкнено"

if ($global:sftpConfig.Enabled) {
    # Тест SFTP підключення: помилкою вважаємо тільки ненульовий ExitCode WinSCP.
    Write-Log "[TEST] Перевірка SFTP підключення..." -Level "INFO"
    $testLog = New-SafeTempFilePath -Prefix "winscp_connection_test" -Extension ".log"
    $testScript = New-SafeTempFilePath -Prefix "winscp_test" -Extension ".txt"
    $sftpTarget = $global:credentialTargets.SFTP
    $sftpCredential = Get-WindowsCredential -Target $sftpTarget
    $sftpConfigValid = Test-SFTPConnection
    $sftpTestExitCode = 1

    if ($sftpConfigValid -and $sftpCredential) {
        $sftpUsername = Escape-WinSCPScriptValue -Value $sftpCredential.Username
        $sftpPassword = Escape-WinSCPScriptValue -Value $sftpCredential.Password
        $sftpHostKey = Escape-WinSCPScriptValue -Value $global:sftpConfig.HostKey
        $sftpPort = $global:sftpConfig.Port
        $sftpTimeout = if ($global:sftpConfig.Timeout) { $global:sftpConfig.Timeout } else { 30 }
        $sftpOpenUrl = Escape-WinSCPScriptValue -Value "sftp://$($global:sftpConfig.Server):$sftpPort/"

        @"
option batch abort
option confirm off
open "$sftpOpenUrl" -username="$sftpUsername" -password="$sftpPassword" -hostkey="$sftpHostKey" -timeout=$sftpTimeout
exit
"@ | Out-File -LiteralPath $testScript -Encoding ASCII

        & $winSCPPath /log=$testLog /script=$testScript | Out-Null
        $sftpTestExitCode = $LASTEXITCODE
    }

    if ($sftpConfigValid -and $sftpCredential -and $sftpTestExitCode -eq 0) {
        Write-Log "[OK] SFTP підключення перевірено" -Level "SUCCESS"
        Remove-SafeTempFile -Path $testLog
    } elseif ($sftpConfigValid -and $sftpCredential) {
        Write-Log "SFTP тест підключення не пройдено (код: $sftpTestExitCode). Лог WinSCP: $testLog" -Level "ERROR"
        if (Test-Path $testLog) {
            $logContent = Get-Content $testLog
            foreach ($line in $logContent) {
                if ($line -match "Error|Failed|Cannot|Permission|refused|timeout|Host key|No such|Access denied") {
                    Write-Log "SFTP TEST: $line" -Level "ERROR"
                } elseif ($line -match "Looking up host|Connecting to host|Starting the session|Authenticated|Connected|Success") {
                    Write-Log "SFTP TEST: $line" -Level "DEBUG"
                }
            }
        }
    }

    Remove-SafeTempFile -Path $testScript
    Write-SectionHeader "ЗАВАНТАЖЕННЯ НА SFTP СЕРВЕР"
    Write-Log "WinSCP: $winSCPPath" -Level "DEBUG"
    Write-Log "SFTP сервер: $($global:sftpConfig.Server)" -Level "DEBUG"
    Write-Log "SFTP користувач: $($global:sftpConfig.Username)" -Level "DEBUG"
    Write-Log "SFTP Credential Manager target: $sftpTarget" -Level "DEBUG"
    
    Write-Log "====================================================================================================" -Level "INFO"
    Write-Log "[SFTP] ЗАВАНТАЖЕННЯ НА SFTP СЕРВЕР" -Level "INFO"
    Write-Log "====================================================================================================" -Level "INFO"
    
    if (-not $winSCPPath) {
        $sftpSuccess = $false
        $sftpStatusText = "ПОМИЛКА (WinSCP не знайдено)"
        Write-Host "[!!] WinSCP не знайдено. Неможливо виконати SFTP завантаження." -ForegroundColor Red
        Write-Log "[!!] WinSCP не знайдено. SFTP завантаження неможливе." -Level "ERROR"
    } elseif (-not $sftpConfigValid) {
        $sftpSuccess = $false
        $sftpStatusText = "ПОМИЛКА (налаштування)"
        Write-Host "[!!] SFTP налаштування некоректні. Перевірте конфігурацію." -ForegroundColor Red
        Write-Log "[!!] SFTP налаштування некоректні. Перевірте конфігурацію." -Level "ERROR"
    } elseif ($sftpTestExitCode -ne 0) {
        $sftpSuccess = $false
        $sftpStatusText = "ПОМИЛКА (тест підключення)"
        Write-Host "[!!] Тест SFTP підключення не пройдено. Перевірте запис '$sftpTarget' у диспетчері облікових даних Windows." -ForegroundColor Red
        Write-Host "     Лог WinSCP: $testLog" -ForegroundColor Gray
        Write-Log "[!!] Тест SFTP підключення не пройдено. WinSCP exit code: $sftpTestExitCode" -Level "ERROR"
    } else {
        Write-Host "Сховище         $($global:sftpConfig.Server):$($global:sftpConfig.Port)$($global:sftpConfig.RemotePath)" -ForegroundColor Gray
        
        foreach ($archiveType in $results.Keys) {
            if ($results[$archiveType].ArchiveSuccess -and $results[$archiveType].HashSuccess) {
                $remoteFolder = switch ($archiveType) {
                    "BLOG"      { "blog" }
                    "BRAVOEXCH" { "bravoexch" }
                    default     { "model" }
                }
                
                $sftpTotalCount += 2
                
                $archivePath = $results[$archiveType].ArchivePath
                $archiveName = Split-Path $archivePath -Leaf
                $archiveSizeBytes = (Get-Item $archivePath -ErrorAction SilentlyContinue).Length
                $archiveSizeMB = [math]::Round($archiveSizeBytes / 1MB, 1)
                $archiveSizeStr = Format-SizeMB -SizeMB $archiveSizeMB
                
                $displayName = switch ($archiveType) {
                    "BLOG"      { "BLOG" }
                    "BRAVOEXCH" { "BRAVOEXCH" }
                    default     { "MODEL" }
                }
                
                Write-Log "SFTP завантаження для $displayName..." -Level "INFO"
                
                # Завантаження архіву
                $archiveUploadSuccess = Upload-ToSFTP -LocalFilePath $archivePath -RemoteSubPath $remoteFolder -DisplayName "$displayName (архів)"
                if ($archiveUploadSuccess) { $sftpSuccessCount++ }
                
                # Завантаження хешу
                $hashPath = $results[$archiveType].HashPath
                $hashUploadSuccess = Upload-ToSFTP -LocalFilePath $hashPath -RemoteSubPath $remoteFolder -DisplayName "$displayName (хеш)"
                if ($hashUploadSuccess) { $sftpSuccessCount++ }
                
                if ($archiveUploadSuccess -and $hashUploadSuccess) {
                    Write-CompactResult -Icon "✓" -Label $displayName -Detail $archiveSizeStr -Status "завантажено" -Color "Green"
                } else {
                    Write-CompactResult -Icon "✕" -Label $displayName -Detail $archiveSizeStr -Status "ПОМИЛКА" -Color "Red"
                }
            }
        }
        
        Write-Host ""
        if ($sftpSuccessCount -gt 0) {
            $sftpSuccess = ($sftpSuccessCount -eq $sftpTotalCount)
            $sftpStatusText = if ($sftpSuccess) { "Успішно ($sftpSuccessCount з $sftpTotalCount)" } else { "ПОМИЛКА ($sftpSuccessCount з $sftpTotalCount)" }
            Write-Host "✓ SFTP: $sftpSuccessCount/$sftpTotalCount файлів" -ForegroundColor Green
            Write-Log "[OK] SFTP завантажено файлів: $sftpSuccessCount з $sftpTotalCount." -Level "SUCCESS"
        } else {
            $sftpSuccess = $false
            $sftpStatusText = "ПОМИЛКА (0 з $sftpTotalCount)"
            Write-Host "[!!] Не вдалося завантажити жодного файлу на SFTP." -ForegroundColor Red
            Write-Log "[!!] Не вдалося завантажити жодного файлу на SFTP." -Level "ERROR"
        }
    }
    Write-Log "====================================================================================================" -Level "INFO"
}
    
# ========================
# 5. ОЧИЩЕННЯ СТАРИХ ФАЙЛІВ
# ========================
if ($enableArchiveDeletion) {
    Write-SectionHeader "ОЧИЩЕННЯ СТАРИХ ФАЙЛІВ"
    Write-Host "Зберігати       $archiveVersions версій" -ForegroundColor Gray
    
    Write-Log "====================================================================================================" -Level "INFO"
    Write-Log "[DEL] ОЧИЩЕННЯ СТАРИХ ФАЙЛІВ (Ротація: $archiveVersions версій)" -Level "INFO"
    Write-Log "====================================================================================================" -Level "INFO"
    
    $totalDeleted = 0
    $totalFreedBytes = 0
    $deletedItems = @()
    
    foreach ($type in @("Model", "Blog", "BravoExch")) {
        $dir = $archiveDirs[$type]
        $active = switch ($type) {
            "Model" { $componentsToArchive.MODEL }
            "Blog" { $componentsToArchive.BLOG }
            "BravoExch" { $componentsToArchive.BRAVOEXCH }
        }
        $displayName = switch ($type) {
            "Model" { "MODEL" }
            "Blog" { "BLOG" }
            "BravoExch" { "BRAVOEXCH" }
        }
        
        if ($active -and (Test-Path $dir)) {
            $allFiles = Get-ChildItem -Path $dir -File | Where-Object { $_.Name -match "\.(mdz|sha512)$" }
            
            $groups = @{}
            foreach ($file in $allFiles) {
                $baseName = $file.Name -replace '\.sha512$', ''
                if (-not $groups.ContainsKey($baseName)) {
                    $groups[$baseName] = @()
                }
                $groups[$baseName] += $file
            }
            
            $sortedGroups = $groups.Keys | Sort-Object { 
                $match = [regex]::Match($_, '(\d{8}_\d{4})')
                if ($match.Success) { [datetime]::ParseExact($match.Value, 'yyyyMMdd_HHmm', $null) }
                else { Get-Item (Join-Path $dir $_) | Select-Object -ExpandProperty LastWriteTime }
            } -Descending
            
            if ($sortedGroups.Count -gt $archiveVersions) {
                $toDeleteGroups = $sortedGroups | Select-Object -Skip $archiveVersions
                
                foreach ($baseName in $toDeleteGroups) {
                    $groupFiles = $groups[$baseName]
                    $deletedCountInGroup = 0
                    $freedBytesInGroup = 0
                    
                    foreach ($file in $groupFiles) {
                        $freedBytesInGroup += $file.Length
                        $deletedCountInGroup++
                        Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                    }
                    
                    $totalDeleted += $deletedCountInGroup
                    $totalFreedBytes += $freedBytesInGroup
                    
                    $archiveFile = $groupFiles | Where-Object { $_.Name -notmatch '\.sha512$' } | Select-Object -First 1
                    $archiveSizeMB = if ($archiveFile) { [math]::Round($archiveFile.Length / 1MB, 2) } else { 0 }
                    $archiveSizeStr = Format-SizeMB -SizeMB $archiveSizeMB -Width 0 -Decimals 2
                    
                    $deletedItems += @{
                        DisplayName = $displayName
                        ArchiveName = $baseName
                        Size = $archiveSizeStr
                        FileCount = $deletedCountInGroup
                        FreedBytes = $freedBytesInGroup
                    }
                }
            }
        }
    }
    
    if ($deletedItems.Count -gt 0) {
        $deletedSummary = @{}
        foreach ($deletedItem in $deletedItems) {
            $name = [string]$deletedItem["DisplayName"]
            if (-not $deletedSummary.ContainsKey($name)) {
                $deletedSummary[$name] = @{
                    Комплекти = 0
                    Файли = 0
                    Розмір = 0
                }
            }

            $deletedSummary[$name]["Комплекти"] += 1
            $deletedSummary[$name]["Файли"] += [int]$deletedItem["FileCount"]
            $deletedSummary[$name]["Розмір"] += [int64]$deletedItem["FreedBytes"]
        }

        foreach ($name in @("MODEL", "BLOG", "BRAVOEXCH")) {
            if (-not $deletedSummary.ContainsKey($name)) { continue }

            $packageCount = $deletedSummary[$name]["Комплекти"]
            $fileCount = $deletedSummary[$name]["Файли"]
            $freedBytes = $deletedSummary[$name]["Розмір"]
            $freedSize = Format-SizeMB -SizeMB ([math]::Round($freedBytes / 1MB, 2)) -Width 0 -Decimals 2
            $packageWord = Get-PackageWord -Count $packageCount
            $fileWord = Get-FileWord -Count $fileCount
            Write-CompactResult -Icon "•" -Label $name -Detail $freedSize -Status "видалено $packageCount $packageWord / $fileCount $fileWord" -Color "DarkYellow"
        }
        Write-Host ""
        
        $freedMB = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F2}", ($totalFreedBytes / 1MB))
        Write-Host "✓ Ротація: видалено $totalDeleted файлів, звільнено $freedMB MB" -ForegroundColor Green
        Write-Log "[DEL] Ротацію завершено. Видалено $totalDeleted файлів, звільнено $freedMB MB" -Level "SUCCESS"
    } else {
        Write-Host "✓ Ротація: нічого видаляти" -ForegroundColor Green
        Write-Log "[DEL] Ротацію завершено. Застарілих файлів не знайдено" -Level "INFO"
    }
    
    Write-Log "====================================================================================================" -Level "INFO"
}
    
# ========================
# 6. ПІДСУМКИ
# ========================
$successCount = 0
$totalCount = 0
$hashSuccessCount = 0

foreach ($key in $results.Keys) {
    if (-not $results[$key].Skipped) {
        $totalCount++
        if ($results[$key].ArchiveSuccess) { $successCount++ }
        if ($results[$key].HashSuccess) { $hashSuccessCount++ }
    }
}

Write-SectionHeader "ПІДСУМОК"

Write-Log "====================================================================================================" -Level "INFO"
Write-Log "[SUM] ПІДСУМОК ВИКОНАННЯ" -Level "INFO"
Write-Log "====================================================================================================" -Level "INFO"

$archiveStatus = if ($successCount -eq $totalCount -and $totalCount -gt 0) { "Успішно ($successCount з $totalCount)" } else { "ПОМИЛКА ($successCount з $totalCount)" }
$archiveColor = if ($successCount -eq $totalCount -and $totalCount -gt 0) { "Green" } else { "Red" }
$archiveIcon = if ($successCount -eq $totalCount -and $totalCount -gt 0) { "✔" } else { "✘" }
Write-CompactResult -Icon $archiveIcon -Label "АРХІВИ" -Detail "Комплекти даних" -Status $archiveStatus -Color $archiveColor

$hashStatus = if ($hashSuccessCount -eq $totalCount -and $totalCount -gt 0) { "Успішно ($hashSuccessCount з $totalCount)" } else { "ПОМИЛКА ($hashSuccessCount з $totalCount)" }
$hashColor = if ($hashSuccessCount -eq $totalCount -and $totalCount -gt 0) { "Green" } else { "Red" }
$hashIcon = if ($hashSuccessCount -eq $totalCount -and $totalCount -gt 0) { "✔" } else { "✘" }
Write-CompactResult -Icon $hashIcon -Label "ХЕШІ" -Detail "SHA512" -Status $hashStatus -Color $hashColor

if ($enableSync.BAZA_Local) {
    $localSyncStatus = if ($syncLocalSuccess) { "Успішно (BAZA)" } else { "ПОМИЛКА (BAZA)" }
    $localSyncColor = if ($syncLocalSuccess) { "Green" } else { "Red" }
    $localSyncIcon = if ($syncLocalSuccess) { "✔" } else { "✘" }
    Write-CompactResult -Icon $localSyncIcon -Label "СИНХ_ЛОК" -Detail "BAZA локально" -Status $localSyncStatus -Color $localSyncColor
}

if ($enableSync.BAZA_Network) {
    $networkSyncStatus = if ($syncNetworkSuccess) { "Успішно (BAZA)" } else { "ПОМИЛКА (BAZA)" }
    $networkSyncColor = if ($syncNetworkSuccess) { "Green" } else { "Red" }
    $networkSyncIcon = if ($syncNetworkSuccess) { "✔" } else { "✘" }
    Write-CompactResult -Icon $networkSyncIcon -Label "СИНХ_МЕР" -Detail "BAZA в мережу" -Status $networkSyncStatus -Color $networkSyncColor
}

if ($enableNetworkCopy -and $copySuccess -gt 0) {
    $copiedPackages = [int]($copySuccess / 2)
    $packageWord = Get-PackageWord -Count $copiedPackages
    $copyExpectedFiles = $successfulArchives * 2
    $copyFileWord = Get-FileWord -Count $copyExpectedFiles
    $copyStatus = if ($copySuccess -eq $copyExpectedFiles) { "Успішно ($copiedPackages $packageWord)" } else { "ПОМИЛКА ($copySuccess з $copyExpectedFiles $copyFileWord)" }
    $copyColor = if ($copySuccess -eq ($successfulArchives * 2)) { "Green" } else { "Red" }
    $copyIcon = if ($copySuccess -eq ($successfulArchives * 2)) { "✔" } else { "✘" }
    Write-CompactResult -Icon $copyIcon -Label "МЕРЕЖА" -Detail "Архіви + SHA512" -Status $copyStatus -Color $copyColor
}

if ($global:sftpConfig.Enabled) {
    $sftpColorText = if ($sftpSuccess) { "Green" } else { "Red" }
    $sftpIcon = if ($sftpSuccess) { "✔" } else { "✘" }
    Write-CompactResult -Icon $sftpIcon -Label "SFTP" -Detail "Віддалене сховище" -Status $sftpStatusText -Color $sftpColorText
}

Write-Host ""

$allSuccessful = ($successCount -eq $totalCount -and $totalCount -gt 0) -and `
                 ($hashSuccessCount -eq $totalCount -and $totalCount -gt 0) -and `
                 (-not $enableSync.BAZA_Local -or $syncLocalSuccess) -and `
                 (-not $enableSync.BAZA_Network -or $syncNetworkSuccess)

if ($enableNetworkCopy -and $successfulArchives -gt 0) {
    $allSuccessful = $allSuccessful -and ($copySuccess -eq ($successfulArchives * 2))
}

if ($global:sftpConfig.Enabled) {
    $allSuccessful = $allSuccessful -and $sftpSuccess
}

Write-Log "====================================================================================================" -Level "INFO"

# ========================
# 7. ЗАВЕРШЕННЯ
# ========================
$scriptEndTime = Get-Date
$duration = $scriptEndTime - $scriptStartTime

$durationFormatted = $duration.ToString('hh\:mm\:ss')
if ($allSuccessful) {
    Write-Host "✓ Готово   $durationFormatted   $($scriptStartTime.ToString('HH:mm:ss')) → $($scriptEndTime.ToString('HH:mm:ss'))" -ForegroundColor Green
    Write-Log "[OK] Усі завдання скрипта виконано без помилок." -Level "SUCCESS"
    Write-Log "[OK] Скрипт успішно виконано. Тривалість: $durationFormatted" -Level "SUCCESS"
} else {
    Write-Host "⚠ Завершено з помилками   $durationFormatted   $($scriptStartTime.ToString('HH:mm:ss')) → $($scriptEndTime.ToString('HH:mm:ss'))" -ForegroundColor Yellow
    Write-Log "[!] Скрипт виконано з помилками. Тривалість: $durationFormatted" -Level "WARNING"
}

Write-ConsoleSeparator

Write-Log "=== ЗАВЕРШЕННЯ РОБОТИ СКРИПТА ===" -Level "INFO"
Write-Log ("Час початку: " + $scriptStartTime.ToString('yyyy-MM-dd HH:mm:ss')) -Level "INFO"
Write-Log ("Час завершення: " + $scriptEndTime.ToString('yyyy-MM-dd HH:mm:ss')) -Level "INFO"
Write-Log ("Тривалiсть: " + $duration.ToString('hh\:mm\:ss')) -Level "INFO"
Write-Log "====================================================================================================" -Level "INFO"

$isInteractive = [Environment]::UserInteractive
$isPowerShellISE = $Host.Name -like "*ISE*"
$isConsole = $Host.Name -like "*ConsoleHost*"

if (-not $global:BravoScheduledTaskRun -and $isInteractive -and $isConsole -and -not $isPowerShellISE) {
    try {
        Write-Host "`nНатисніть Enter для закриття..." -ForegroundColor Yellow
        Read-Host
    } catch {
        Write-Host "`nНатисніть Enter для закриття..." -ForegroundColor Yellow
        Read-Host
    }
} elseif (-not $global:BravoScheduledTaskRun -and $isInteractive) {
    Write-Host "`nНатисніть Enter для закриття..." -ForegroundColor Yellow
    Read-Host
}

}

