# ==================================================================================================
# BRAVO Archive / Restore / Verified Archive
# ==================================================================================================

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

    $extractParams = @($SevenZipExtractArgs) + @(
        "-o$Destination",
        "-p$ArchivePassword",
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

function Invoke-Bravo7ZipSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Write-Log "$Description..." -Level "INFO"

    $maskedArgs = @()
    foreach ($arg in @($Arguments)) {
        $argText = [string]$arg
        if ($argText -like "-p*") {
            $maskedArgs += "-p***"
        }
        else {
            $maskedArgs += $argText
        }
    }

    Write-Log "7-Zip: $Command $($maskedArgs -join ' ')" -Level "DEBUG"

    try {
        $output = & $Command @Arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        if (-not [string]::IsNullOrWhiteSpace($output)) {
            Write-Log "7-Zip output:$output" -Level "DEBUG"
        }

        if ($exitCode -eq 0) {
            Write-Log "$Description успішно завершено" -Level "SUCCESS"
        }
        elseif ($exitCode -eq 1) {
            Write-Log "$Description завершено з попередженнями. Код: $exitCode" -Level "WARNING"
        }
        else {
            Write-Log "ПОМИЛКА під час $Description. Код: $exitCode" -Level "ERROR"
        }

        return [int]$exitCode
    }
    catch {
        Write-Log "ПОМИЛКА під час ${Description}: $($_.Exception.Message)" -Level "ERROR"
        return 1
    }
}

function Expand-BravoArchiveToken {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    $expanded = [string]$Value
    $expanded = $expanded.Replace("{ROOT_LIMS}", [string]$ROOT_LIMS)
    $expanded = $expanded.Replace("{ARC_DIR}", [string]$ARC_DIR)
    $expanded = $expanded.Replace("{LOG_DIR}", [string]$LOG_DIR)
    $expanded = $expanded.Replace("{ArchivePrefix}", [string]$ArchivePrefix)

    return [Environment]::ExpandEnvironmentVariables($expanded)
}

function New-BravoSafeTempArchivePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FinalArchivePath
    )

    $archiveDir = Split-Path -Path $FinalArchivePath -Parent

    $configuredTempDir = Get-BravoConfigValue -Name "ArchiveTempDir" -Default "{ROOT_LIMS}\ARCHIV\TEMP"
    $tempRoot = Expand-BravoArchiveToken -Value ([string]$configuredTempDir)

    if ([string]::IsNullOrWhiteSpace($tempRoot)) {
        $tempRoot = Join-Path -Path $ROOT_LIMS -ChildPath "ARCHIV\TEMP"
    }

    if (-not (Test-Path -LiteralPath $tempRoot)) {
        New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    }

    $extension = [System.IO.Path]::GetExtension($FinalArchivePath)
    if ([string]::IsNullOrWhiteSpace($extension)) {
        $extension = ".mdz"
    }

    $safePrefix = [System.IO.Path]::GetFileNameWithoutExtension($FinalArchivePath)
    $safePrefix = $safePrefix -replace '[^A-Za-z0-9_\-]', '_'

    return Join-Path -Path $tempRoot -ChildPath ("archive_{0}_{1}{2}" -f $safePrefix, ([guid]::NewGuid().ToString("N")), $extension)
}

function Remove-BravoSafeTempArchive {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (Test-Path -LiteralPath $Path -ErrorAction SilentlyContinue) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    }
}

function Test-BravoArchiveSourcePath {
    param([string]$SourcePath)

    if ([string]::IsNullOrWhiteSpace($SourcePath)) {
        return $false
    }

    $sourceToCheck = $SourcePath

    if ($sourceToCheck.EndsWith("\*")) {
        $sourceToCheck = $sourceToCheck.Substring(0, $sourceToCheck.Length - 2)
    }

    return (Test-Path -Path $sourceToCheck)
}

function New-BravoVerifiedArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath,

        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [array]$ArcCommonParams,

        [Parameter(Mandatory = $true)]
        [string]$ARC_PATH,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $archiveName = [System.IO.Path]::GetFileName($ArchivePath)
    $archiveDir = Split-Path -Path $ArchivePath -Parent
    $tempArchivePath = $null

    if (-not (Test-Path -LiteralPath $archiveDir)) {
        New-Item -ItemType Directory -Path $archiveDir -Force | Out-Null
    }

    if (-not (Test-BravoArchiveSourcePath -SourcePath $SourcePath)) {
        $errorMsg = "${Description}: джерело не знайдено: $SourcePath"
        Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
        return $false
    }

    $tempArchivePath = New-BravoSafeTempArchivePath -FinalArchivePath $ArchivePath

    Write-Log "${Description}: тимчасовий архів: $tempArchivePath" -Level "DEBUG"
    Write-Log "${Description}: фінальний архів після перевірки: $ArchivePath" -Level "DEBUG"

    try {
        $createArgs = @($ArcCommonParams) + @($tempArchivePath, $SourcePath)
        $createExitCode = Invoke-Bravo7ZipSafe `
            -Command $ARC_PATH `
            -Arguments $createArgs `
            -Description "$Description (тимчасовий архів)"

        if (($createExitCode -ne 0 -and $createExitCode -ne 1) -or -not (Test-Path -LiteralPath $tempArchivePath)) {
            $errorMsg = "${Description}: тимчасовий архів не створено або 7-Zip повернув код $createExitCode. Файл: $tempArchivePath"
            Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            Remove-BravoSafeTempArchive -Path $tempArchivePath
            $global:criticalErrorOccurred = $true
            return $false
        }

        if ($createExitCode -eq 1) {
            Write-Log "${Description}: 7-Zip створив архів із попередженнями, виконується обов'язкова перевірка цілісності." -Level "WARNING"
        }

        $testArgs = @("t")

        if ($ArchivePasswordEnabled -eq "on" -and -not [string]::IsNullOrWhiteSpace($ArchivePassword)) {
            $testArgs += "-p$ArchivePassword"
        }

        $testArgs += $tempArchivePath

        $testExitCode = Invoke-Bravo7ZipSafe `
            -Command $ARC_PATH `
            -Arguments $testArgs `
            -Description "$Description (перевірка 7-Zip)"

        if ($testExitCode -ne 0) {
            $errorMsg = "${Description}: архів не пройшов перевірку 7-Zip. Код: $testExitCode. Тимчасовий файл видалено: $tempArchivePath"
            Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
            Send-SlackAlert -Message $errorMsg -IsCritical
            Remove-BravoSafeTempArchive -Path $tempArchivePath
            $global:criticalErrorOccurred = $true
            return $false
        }

        Write-Log "${Description}: тимчасовий архів пройшов перевірку 7-Zip" -Level "SUCCESS"

        if (Test-Path -LiteralPath $ArchivePath) {
            Write-Log "${Description}: фінальний архів уже існує і буде замінений після успішної перевірки: $ArchivePath" -Level "WARNING"
            Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction Stop
        }

        if (Test-Path -LiteralPath "$ArchivePath.sha512") {
            Remove-Item -LiteralPath "$ArchivePath.sha512" -Force -ErrorAction SilentlyContinue
        }

        Move-Item -LiteralPath $tempArchivePath -Destination $ArchivePath -Force -ErrorAction Stop

        if (-not (Test-Path -LiteralPath $ArchivePath)) {
            throw "Final archive was not found after move: $ArchivePath"
        }

        Write-Log "${Description}: архів перевірено та перенесено в основне сховище: $ArchivePath" -Level "SUCCESS"
        return $true
    }
    catch {
        $errorMsg = "${Description}: помилка verified-архівації: $($_.Exception.Message)"
        Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        Remove-BravoSafeTempArchive -Path $tempArchivePath
        $global:criticalErrorOccurred = $true
        return $false
    }
}

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
            $archiveOk = New-BravoVerifiedArchive `
                -ArchivePath $archivePath `
                -SourcePath $dir.FullName `
                -ArcCommonParams $arcCommonParams `
                -ARC_PATH $ARC_PATH `
                -Description "Архівація $dirName"
            
            if ($archiveOk) {
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