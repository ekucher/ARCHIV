# ==============================================================================
# BRAVO.Maintenance.Checks.ps1
# Автоматично винесені функції з BRAVO_MAINTENANCE.ps1
# ==============================================================================

function Test-DiskSpace {
    param(
        [int]$CheckHours = $DISK_SPACE_CHECK_HOURS,
        [int]$WarningPercent = $DISK_SPACE_WARNING_PERCENT,
        [int]$CriticalPercent = $DISK_SPACE_CRITICAL_PERCENT,
        [int]$MinFreeGB = $DISK_SPACE_MIN_FREE_GB,
        [array]$ExcludeDrives = $DISK_EXCLUDE_LIST
    )
    
    # Виводимо заголовок без зайвих рядків
    Write-MaintenanceLog -Message "=== ПЕРЕВІРКА ДИСКІВ ===" -NoTimestamp
    
    $allDrives = Get-PSDrive -PSProvider FileSystem | Where-Object { 
        $_.Root -match '^[A-Z]:\\$' -and 
        $_.Used -gt 0 -and 
        $_.Root -notin $ExcludeDrives
    }
    
    if (-not $allDrives) {
        Write-MaintenanceLog "✕ Не знайдено дисків для перевірки" -Level "ERROR"
        return $false
    }
    
    $allOk = $true
    $diskStatus = @()
    $problemDisksDetails = @()
    $hasAnyProblem = $false
    
    foreach ($drive in $allDrives) {
        $driveLetter = $drive.Root.TrimEnd('\')
        $driveLabel = $driveLetter.TrimEnd(':')
        
        $totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
        $freeGB = [math]::Round($drive.Free / 1GB, 2)
        $freePercent = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 1)
        $usedPercent = [math]::Round(($drive.Used / ($drive.Used + $drive.Free)) * 100, 1)
        
        # Визначаємо статус
        $isError = $false
        $icon = "✓"
        $statusText = ""
        $warningType = $null
        
        if ($freeGB -lt $MinFreeGB) {
            $isError = $true
            $hasAnyProblem = $true
            $allOk = $false
            $icon = "✕"
            $statusText = "КРИТИЧНО"
            $warningType = "critical_space"
            $global:CriticalErrorsList.Add("${driveLabel}: критично мало вільного місця (${freeGB} GB, мінімум ${MinFreeGB} GB)")
        }
        elseif ($freePercent -le $CriticalPercent) {
            $isError = $true
            $hasAnyProblem = $true
            $allOk = $false
            $icon = "✕"
            $statusText = "КРИТИЧНО"
            $warningType = "critical_percent"
            $global:CriticalErrorsList.Add("${driveLabel}: критично мало вільного місця (${freePercent}%, ліміт ${CriticalPercent}%)")
        }
        elseif ($freePercent -le $WarningPercent) {
            $isError = $true
            $hasAnyProblem = $true
            $allOk = $false
            $icon = "!"
            $statusText = "ПОПЕРЕДЖЕННЯ"
            $warningType = "warning"
            $global:CriticalErrorsList.Add("${driveLabel}: мало вільного місця (${freePercent}%, ліміт ${WarningPercent}%)")
        }
        
        # Короткий рядок статусу для консолі
        $diskStatus += "${driveLabel}: ${icon} ${freePercent}% (${freeGB}/${totalGB} GB) | ${usedPercent}%"
        
        # Детальна інформація для Slack (тільки проблеми)
        if ($isError) {
            $problemDisksDetails += "• *${driveLetter}*"
            $problemDisksDetails += "  └ 💾 Всього: ${totalGB} GB"
            $problemDisksDetails += "  └ 📊 Вільно: ${freeGB} GB (${freePercent}%)"
            $problemDisksDetails += "  └ 📈 Використано: ${usedPercent}%"
            $problemDisksDetails += "  └ ! Проблема: ${statusText}"
            if ($warningType -eq "critical_space") {
                $problemDisksDetails += "  └ 🔴 Критично мало місця (менше ${MinFreeGB} GB)"
            } elseif ($warningType -eq "critical_percent") {
                $problemDisksDetails += "  └ 🔴 Критично мало місця (менше ${CriticalPercent}%)"
            } elseif ($warningType -eq "warning") {
                $problemDisksDetails += "  └ 🟡 Мало вільного місця (менше ${WarningPercent}%)"
            }
            $problemDisksDetails += ""
        }
    }
    
    # Виводимо зведення в консоль (без зайвих рядків)
    foreach ($line in $diskStatus) { 
        Write-MaintenanceLog -Message "$line" -Level "INFO"
    }
    
    # Зберігаємо деталі проблемних дисків для фінального звіту
    if ($hasAnyProblem -and $problemDisksDetails) {
        $global:DiskSpaceDetails = $problemDisksDetails
    }
    
    # Виводимо підсумок без зайвого рядка
    if ($allOk) {
        Write-Success "Усі диски в нормі"
    } else {
        Write-ErrorLog "Виявлено проблеми з дисками"
    }
    
    return $allOk
}

function Test-BackupIntegrity {
    param(
        [int]$MaxHoursOld = 24,
        [string]$RootPath
    )
    
    Write-ActionHeader -Header "ПЕРЕВІРКА СВІЖОСТІ РЕЗЕРВНИХ КОПІЙ"    $defaultArchiveRoot = if ($global:archivPath) { $global:archivPath } else { Join-Path $RootPath "ARCHIV" }
    $modelArchivePath = if ($global:archiveDirs -and $global:archiveDirs.Model) { $global:archiveDirs.Model } else { Join-Path $defaultArchiveRoot "MODEL" }
    $blogArchivePath = if ($global:archiveDirs -and $global:archiveDirs.Blog) { $global:archiveDirs.Blog } else { Join-Path $defaultArchiveRoot "BLOG" }
    $bravoExchArchivePath = if ($global:archiveDirs -and $global:archiveDirs.BravoExch) { $global:archiveDirs.BravoExch } else { Join-Path $defaultArchiveRoot "BRAVOEXCH" }

    $backupDirsToCheck = @(
        @{ Path = $modelArchivePath;     Prefix = $ArchivePrefix;          Name = "MODEL"; ExcludePattern = "before|after" }
        @{ Path = $blogArchivePath;      Prefix = "${ArchivePrefix}_blog"; Name = "BLOG"; ExcludePattern = $null }
        @{ Path = $bravoExchArchivePath; Prefix = "${ArchivePrefix}_bravoexch"; Name = "BRAVOEXCH"; ExcludePattern = $null }
    )
    
    $allOk = $true
    $currentTime = Get-Date
    $cutoffTime = $currentTime.AddHours(-$MaxHoursOld)
    $backupStatus = @()
    $problemArchiveDetailsText = @()
    $hasAnyProblem = $false
    
    foreach ($dirConfig in $backupDirsToCheck) {
        $dirPath = $dirConfig.Path
        $prefix = $dirConfig.Prefix
        $dirName = $dirConfig.Name
        $excludePattern = $dirConfig.ExcludePattern
        
        if (-not (Test-Path $dirPath)) {
            $errorMsg = "Каталог відсутній: $dirPath"
            Write-ErrorLog $errorMsg
            $allOk = $false
            $hasAnyProblem = $true
            $backupStatus += "${dirName}: ✕ Каталог відсутній"
            $global:CriticalErrorsList.Add("${dirName}: каталог не існує (${dirPath})")
            $problemArchiveDetailsText += "• *${dirName}*: ✕ КАТАЛОГ ВІДСУТНІЙ - неможливо перевірити архіви"
            $problemArchiveDetailsText += ""
            continue
        }
        
        $allMdzFiles = Get-ChildItem -Path $dirPath -Filter "${prefix}_*.mdz" -ErrorAction SilentlyContinue
        
        if ($excludePattern) {
            $mdzFiles = $allMdzFiles | Where-Object { $_.Name -notmatch $excludePattern } | Sort-Object LastWriteTime -Descending
            $excludedFiles = $allMdzFiles | Where-Object { $_.Name -match $excludePattern }
            if ($excludedFiles -and $global:LogLevel -eq "DEBUG") {
                Write-MaintenanceLog "Виключено з перевірки архіви реставрації: $($excludedFiles.Count) файлів" -Level "DEBUG"
            }
        } else {
            $mdzFiles = $allMdzFiles | Sort-Object LastWriteTime -Descending
        }
        
        if (-not $mdzFiles) {
            $errorMsg = "Не знайдено жодного файлу .mdz у ${dirPath} з префіксом ${prefix}"
            Write-ErrorLog $errorMsg
            $allOk = $false
            $hasAnyProblem = $true
            $backupStatus += "${dirName}: ✕ Немає файлів .mdz"
            $global:CriticalErrorsList.Add("${dirName}: відсутні архіви .mdz")
            $problemArchiveDetailsText += "• *${dirName}*: ✕ АРХІВИ ВІДСУТНІ"
            $problemArchiveDetailsText += ""
            continue
        }
        
        $latestArchive = $mdzFiles[0]
        $archiveTime = $latestArchive.LastWriteTime
        $ageHours = ($currentTime - $archiveTime).TotalHours
        $archiveSize = Format-FileSize $latestArchive.Length
        $archiveName = $latestArchive.Name
        $shaFile = "$($latestArchive.FullName).sha512"
        
        $shaExists = Test-Path $shaFile
        $shaValid = $false
        
        if ($shaExists) {
            try {
                $shaContent = Get-Content $shaFile -Raw -ErrorAction SilentlyContinue
                if ($shaContent -match '^[A-F0-9]{128}') {
                    $shaValid = $true
                }
            } catch {
                $shaValid = $false
            }
        }
        
        $isFresh = ($archiveTime -ge $cutoffTime)
        $ageHoursRounded = [math]::Round($ageHours, 1)
        
        $hasProblem = $false
        
        if (-not $isFresh) {
            $errorMsg = "Архів застарів: $archiveName (вік $ageHoursRounded год > $MaxHoursOld год)"
            Write-ErrorLog $errorMsg
            $allOk = $false
            $hasAnyProblem = $true
            $hasProblem = $true
            $global:CriticalErrorsList.Add("${dirName}: архів застарів (вік $ageHoursRounded год, ліміт $MaxHoursOld год)")
        }
        
        if (-not $shaExists) {
            $global:CriticalErrorsList.Add("${dirName}: відсутній SHA512 для $archiveName")
            Write-ErrorLog "Відсутній SHA512 для $archiveName"
            $hasAnyProblem = $true
            $hasProblem = $true
        } elseif (-not $shaValid) {
            $global:CriticalErrorsList.Add("${dirName}: пошкоджений SHA512 для $archiveName")
            Write-ErrorLog "Пошкоджений SHA512 для $archiveName"
            $hasAnyProblem = $true
            $hasProblem = $true
        }
        
        $freshStatusText = if ($isFresh) { "Свіжий" } else { "Застарів" }
        $shaStatusText = if ($shaExists -and $shaValid) { "✓" } elseif ($shaExists) { "пошкоджено" } else { "відсутній" }

        if ($isFresh -and $shaExists -and $shaValid) {
            $backupStatus += ("✓ {0,-10} {1,5} год   {2,-10}   SHA512: {3,-10} {4}" -f $dirName, $ageHoursRounded, $archiveSize, $shaStatusText, $archiveName)
        } else {
            $backupStatus += ("✕ {0,-10} {1} ({2} год)   {3,-10}   SHA512: {4,-10} {5}" -f $dirName, $freshStatusText, $ageHoursRounded, $archiveSize, $shaStatusText, $archiveName)
        }
        
        if ($hasProblem) {
            $freshStatusIcon = if ($isFresh) { "✓" } else { "✕" }
            $freshStatusText = if ($isFresh) { "Свіжий" } else { "ЗАСТАРІВ" }
            
            if ($shaExists -and $shaValid) {
                $shaStatusIcon = "✓"
                $shaStatusText = "Валідний"
            } elseif ($shaExists) {
                $shaStatusIcon = "!"
                $shaStatusText = "Пошкоджено"
            } else {
                $shaStatusIcon = "✕"
                $shaStatusText = "Відсутній"
            }
            
            $problemArchiveDetailsText += "• *${dirName}*: ${archiveName}"
            $problemArchiveDetailsText += "  └ 📅 Створено: $($archiveTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            $problemArchiveDetailsText += "  └ ⏱️ Вік: ${ageHoursRounded} год (ліміт: ${MaxHoursOld} год) → ${freshStatusIcon} ${freshStatusText}"
            $problemArchiveDetailsText += "  └ 💾 Розмір: ${archiveSize}"
            $problemArchiveDetailsText += "  └ 🔐 SHA512: ${shaStatusIcon} ${shaStatusText}"
            $problemArchiveDetailsText += ""
        }
    }
    
    foreach ($status in $backupStatus) {
        Write-MaintenanceLog -Message " $status" -Level "INFO"
    }
    
    if ($hasAnyProblem) {
        $global:BackupArchiveDetails = $problemArchiveDetailsText
    } else {
        $global:BackupArchiveDetails = $null
    }
    
    Write-MaintenanceLog -Message ""
    if ($allOk) {
        Write-Success "Усі резервні копії свіжі та мають контрольні суми"
    } else {
        Write-ErrorLog "Виявлено проблеми з резервними копіями"
    }
    
    return $allOk
}
