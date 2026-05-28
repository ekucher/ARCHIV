# ==================================================================================================
# BRAVO Files / Logs / Cleanup
# ==================================================================================================

function Format-CommandOutput {
    param([string]$Output)
    return "`n" + ($Output -replace "`r?`n", "`n    ") + "`n"
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

function Move-WithSequence {
    param(
        [string]$sourcePath,
        [string]$destDir,
        [switch]$SkipIfEmpty
    )
    
    if (-not (Test-Path $sourcePath)) {
        Write-Log "[ПОМИЛКА] Файл $([System.IO.Path]::GetFileName($sourcePath)) не знайдено" -Level "ERROR"
        return $false
    }
    
    $fileInfo = Get-Item $sourcePath
    if ($fileInfo.Length -eq 0 -and $SkipIfEmpty) {
        Write-Log "[ІНФО] Пропущено порожній файл: $([System.IO.Path]::GetFileName($sourcePath))" -Level "INFO"
        return $false
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
        return $false
    }

    $suffix = $nextNumber.ToString("000000")
    $newName = "${fileName}_${suffix}${fileExt}"
    $destPath = Join-Path -Path $destDir -ChildPath $newName

    try {
        Move-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction Stop
        Write-Log "Переміщено $([System.IO.Path]::GetFileName($sourcePath)) до $newName" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "[WARNING] Не вдалося перемістити $([System.IO.Path]::GetFileName($sourcePath)): $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

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
            Write-Log "Змін в розмірах файлів не знайдено" -Level "DEBUG"
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
    
    $movedCount = 0
    $skippedCount = 0

    foreach ($file in $logFiles) {
        $moved = Move-WithSequence -sourcePath $file.FullName -destDir $DestDir -SkipIfEmpty

        if ($moved) {
            $movedCount++
        }
        else {
            $skippedCount++
        }
    }

    if ($movedCount -gt 0) {
        Write-Log "Оброблено $movedCount $LogType файлів" -Level "SUCCESS"
    }

    if ($skippedCount -gt 0) {
        Write-Log "Пропущено $skippedCount $LogType файлів, які не вдалося перемістити" -Level "WARNING"
    }
}

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

function Check-MdFileSizes {
    param(
        [string]$MODEL_PATH,
        [int64]$MAX_MD_FILE_SIZE,
        [string[]]$ExcludedFiles = @()
    )

    Write-Log "==="
    Write-Log "=== ПЕРЕВІРКА РОЗМІРІВ .MD ФАЙЛІВ ==="
    Write-Log "Перевірка розмірів файлів .md..." -Level "INFO"

    if (-not (Test-Path $MODEL_PATH)) {
        $errorMsg = "Директорія моделі не знайдена: $MODEL_PATH"
        Write-Log "ПОМИЛКА: $errorMsg" -Level "ERROR"
        Send-SlackAlert -Message $errorMsg -IsCritical
        $global:criticalErrorOccurred = $true
        return
    }

    $displayExclusions = @($ExcludedFiles) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
            $_.Trim().Replace('/', '\')
        }

    $normalizedExclusions = @($displayExclusions) |
        ForEach-Object {
            $_.ToLowerInvariant()
        }

    function Test-MdFileExcluded {
        param(
            [System.IO.FileInfo]$File,
            [string]$BasePath,
            [string[]]$Patterns
        )

        if (-not $Patterns -or $Patterns.Count -eq 0) {
            return $false
        }

        $baseFullPath = (Resolve-Path -LiteralPath $BasePath).Path.TrimEnd('\')
        $fileFullPath = $File.FullName

        if ($fileFullPath.StartsWith($baseFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $relativePath = $fileFullPath.Substring($baseFullPath.Length).TrimStart('\')
        }
        else {
            $relativePath = $File.Name
        }

        $fileNameNormalized = $File.Name.Replace('/', '\').ToLowerInvariant()
        $relativePathNormalized = $relativePath.Replace('/', '\').ToLowerInvariant()

        foreach ($pattern in $Patterns) {
            if ($fileNameNormalized -like $pattern -or $relativePathNormalized -like $pattern) {
                return $true
            }
        }

        return $false
    }

    if ($displayExclusions.Count -gt 0) {
        Write-Log "Виключення з перевірки .md файлів: $($displayExclusions -join ', ')" -Level "INFO"
    }

    $allMdFiles = Get-ChildItem -Path $MODEL_PATH -Recurse -Filter "*.md" -File -ErrorAction SilentlyContinue

    $excludedMdFiles = @(
        $allMdFiles | Where-Object {
            Test-MdFileExcluded -File $_ -BasePath $MODEL_PATH -Patterns $normalizedExclusions
        }
    )

    $largeFiles = @(
        $allMdFiles | Where-Object {
            $_.Length -gt $MAX_MD_FILE_SIZE -and
            -not (Test-MdFileExcluded -File $_ -BasePath $MODEL_PATH -Patterns $normalizedExclusions)
        }
    )

    if ($excludedMdFiles.Count -gt 0) {
        Write-Log "Пропущено за виключеннями .md файлів: $($excludedMdFiles.Count)" -Level "INFO"

        foreach ($file in $excludedMdFiles) {
            $relativePath = $file.FullName.Replace($MODEL_PATH, "").TrimStart('\')
            $sizeFormatted = Format-FileSize $file.Length
            Write-Log "  Виключено: $relativePath : $sizeFormatted" -Level "DEBUG"
        }
    }

    if ($largeFiles.Count -gt 0) {
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
    }
    else {
        Write-Log "Файли .md з розміром більше $($MAX_MD_FILE_SIZE / 1MB) МБ не знайдено." -Level "INFO"
    }
}


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
        Move-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction Stop
        Write-Log "Переміщено $([System.IO.Path]::GetFileName($sourcePath)) до $destDir" -Level "SUCCESS"
        return $true
    }
    catch {
        Write-Log "[WARNING] Не вдалося перемістити $([System.IO.Path]::GetFileName($sourcePath)): $($_.Exception.Message)" -Level "WARNING"
        return $false
    }
}

