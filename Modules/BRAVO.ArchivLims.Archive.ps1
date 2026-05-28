# ==============================================================================
# BRAVO.ArchivLims.Archive.ps1
# Автоматично винесені функції з BRAVO_ARCHIV_LIMS.ps1
# ==============================================================================

function Clear-OldLogs {
    param(
        [string]$LogPath,
        [int]$RetentionDays
    )
    
    if (-not $RetentionDays -or $RetentionDays -le 0) {
        Write-Log "Очищення логів вимкнено (logRetentionDays = $RetentionDays)" -Level "INFO"
        return
    }
    
    Write-Log "Очищення логів старіших за $RetentionDays днів..." -Level "INFO"
    
    $cutoffDate = (Get-Date).AddDays(-$RetentionDays)
    $deletedCount = 0
    
    try {
        $oldLogs = Get-ChildItem -Path $LogPath -Filter "ARCHIV_LIMS_*.log" -ErrorAction SilentlyContinue | 
                    Where-Object { $_.LastWriteTime -lt $cutoffDate }
        
        foreach ($log in $oldLogs) {
            Remove-Item -Path $log.FullName -Force -ErrorAction SilentlyContinue
            $deletedCount++
            Write-Log "  Видалено: $($log.Name)" -Level "DEBUG"
        }
        
        if ($deletedCount -gt 0) {
            Write-Log "Видалено $deletedCount старих лог-файлів" -Level "SUCCESS"
        } else {
            Write-Log "Старих лог-файлів не знайдено" -Level "INFO"
        }
    } catch {
        Write-Log "Помилка очищення логів: $($_.Exception.Message)" -Level "WARNING"
    }
}

function Find-ToolPath {
    param(
        [string]$ToolName,
        [array]$PossiblePaths
    )
    
    Write-Log ("Пошук " + $ToolName + "...") -Level "DEBUG"
    
    foreach ($path in $PossiblePaths) {
        $pathStr = [string]$path
        if (Test-Path $pathStr) {
            Write-Log ("Знайдено " + $ToolName + ": " + $pathStr) -Level "SUCCESS"
            return $pathStr
        }
    }
    
    Write-Log ($ToolName + " не знайдено") -Level "WARNING"
    return $null
}

function New-SafeTempFilePath {
    param(
        [string]$Prefix,
        [string]$Extension = ".tmp"
    )

    $tempDir = Join-Path $logPath "TEMP"
    if (-not (Test-Path $tempDir)) {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
    }

    if (-not $Extension.StartsWith(".")) {
        $Extension = ".$Extension"
    }

    $fileName = "{0}_{1}{2}" -f $Prefix, ([Guid]::NewGuid().ToString("N")), $Extension
    return Join-Path $tempDir $fileName
}

function Remove-SafeTempFile {
    param([string]$Path)

    if ([string]::IsNullOrEmpty($Path)) { return }

    $item = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($item -and -not $item.PSIsContainer) {
        Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
    }
}

function Test-Compatibility {
    Write-Log "Перевiрка сумiсностi системи..." -Level "DEBUG"
    
    $compatibilityIssues = @()
    
    if (Get-Command Get-FileHash -ErrorAction SilentlyContinue) {
        $script:hasFileHash = $true
        Write-Log "Get-FileHash: ДОСТУПНИЙ" -Level "DEBUG"
    } else {
        $script:hasFileHash = $false
        $compatibilityIssues += "Get-FileHash"
        Write-Log "Get-FileHash: НЕ ДОСТУПНИЙ" -Level "DEBUG"
    }
    
    if ($compatibilityIssues.Count -gt 0) {
        $script:compatibilityMode = $true
        Write-Log "УВІМКНЕНО РЕЖИМ СУМІСНОСТІ" -Level "WARNING"
    } else {
        $script:compatibilityMode = $false
        Write-Log "Стандартний режим" -Level "DEBUG"
    }
    
    return $compatibilityIssues
}

function New-SHA512Hash {
    param([string]$FilePath, [string]$HashFilePath)
    
    Write-Log ("Створення SHA512 хешу: " + (Split-Path $FilePath -Leaf)) -Level "DEBUG"
    
    if (-not (Test-Path $FilePath)) {
        Write-Log ("Файл не знайдено: " + $FilePath) -Level "ERROR"
        return $false
    }
    
    try {
        $hash = (Get-FileHash -Path $FilePath -Algorithm SHA512).Hash.ToLower()
        $fileName = (Get-Item $FilePath).Name
        [System.IO.File]::WriteAllText($HashFilePath, "${hash} *${fileName}", [System.Text.Encoding]::UTF8)
        
        Write-Log ("Хеш створено: " + $HashFilePath) -Level "DEBUG"
        return $true
    } catch {
        Write-Log ("Помилка створення хешу: " + $_.Exception.Message) -Level "ERROR"
        return $false
    }
}

function New-Archive {
    param([string]$SourcePath, [string]$ArchivePath, [string]$ArchiveName, [string]$ArcPath, [string]$ArcParams)

    Write-Log ("Створення архiву: " + $ArchiveName) -Level "DEBUG"

    if (-not (Test-Path $ArchivePath)) {
        New-Item -ItemType Directory -Path $ArchivePath -Force | Out-Null
    }

    if (-not (Test-Path $SourcePath)) {
        Write-Log ("Джерело не знайдено: " + $SourcePath) -Level "ERROR"
        return $false
    }

    $finalArchivePath = Join-Path $ArchivePath $ArchiveName
    $archiveExtension = [System.IO.Path]::GetExtension($ArchiveName)
    if ([string]::IsNullOrWhiteSpace($archiveExtension)) { $archiveExtension = ".mdz" }
    $archivePrefix = [System.IO.Path]::GetFileNameWithoutExtension($ArchiveName)
    $archivePrefix = ($archivePrefix -replace '[^A-Za-z0-9_\-]', '_')
    $tempArchivePath = New-SafeTempFilePath -Prefix "archive_$archivePrefix" -Extension $archiveExtension

    try {
        $passwordParams = ""
        $passwordTestParams = ""
        if ($global:enableArchivePassword) {
            $archiveCredential = Get-WindowsCredential -Target $global:credentialTargets.Archive
            if (-not $archiveCredential -or [string]::IsNullOrEmpty($archiveCredential.Password)) {
                Write-Log "Пароль архіву не знайдено в Windows Credential Manager (Target: $($global:credentialTargets.Archive))" -Level "ERROR"
                return $false
            }

            if ($archiveCredential.Password -match '"') {
                Write-Log "Пароль архіву містить подвійні лапки, які не підтримуються для передачі в 7-Zip CLI" -Level "ERROR"
                return $false
            }

            $passwordParams = " -p`"$($archiveCredential.Password)`""
            $passwordTestParams = $passwordParams
            if ($global:archivePasswordEncryptHeaders) {
                $passwordParams += " -mhe=on"
            }
        }

        Write-Log "Тимчасовий архів: $tempArchivePath" -Level "DEBUG"
        Write-Log "Фінальний архів після перевірки: $finalArchivePath" -Level "DEBUG"

        $createArguments = "$ArcParams$passwordParams `"$tempArchivePath`" `"$SourcePath`""
        $createArgumentsForLog = "$ArcParams$(if ($passwordParams) { ' -p***' + $(if ($global:archivePasswordEncryptHeaders) { ' -mhe=on' } else { '' }) } else { '' }) `"$tempArchivePath`" `"$SourcePath`""
        Write-Log "7-Zip створення: $ArcPath $createArgumentsForLog" -Level "DEBUG"

        $processInfo = New-Object System.Diagnostics.ProcessStartInfo
        $processInfo.FileName = $ArcPath
        $processInfo.Arguments = $createArguments
        $processInfo.RedirectStandardOutput = $true
        $processInfo.RedirectStandardError = $true
        $processInfo.UseShellExecute = $false
        $processInfo.CreateNoWindow = $true

        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $processInfo
        $process.Start() | Out-Null
        $createStdOut = $process.StandardOutput.ReadToEnd()
        $createStdErr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()

        Write-Log "7-Zip створення завершено з кодом: $($process.ExitCode)" -Level "DEBUG"
        if (-not [string]::IsNullOrWhiteSpace($createStdOut)) { Write-Log "7-Zip створення STDOUT:`n$createStdOut" -Level "DEBUG" }
        if (-not [string]::IsNullOrWhiteSpace($createStdErr)) { Write-Log "7-Zip створення STDERR:`n$createStdErr" -Level "DEBUG" }

        if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 1) {
            Write-Host " ✘ $ArchiveName - помилка створення тимчасового архіву (код $($process.ExitCode))" -ForegroundColor Red
            Write-Log "Помилка створення тимчасового архіву $ArchiveName. Код 7-Zip: $($process.ExitCode)" -Level "ERROR"
            Remove-SafeTempFile -Path $tempArchivePath
            return $false
        }

        if (-not (Test-Path -LiteralPath $tempArchivePath)) {
            Write-Host " ✘ $ArchiveName - тимчасовий архів не створено" -ForegroundColor Red
            Write-Log "Тимчасовий архів не знайдено після створення: $tempArchivePath" -Level "ERROR"
            return $false
        }

        if ($process.ExitCode -eq 1) {
            Write-Log "7-Zip створив архів із попередженнями. Перед перенесенням буде виконано тест цілісності." -Level "WARNING"
        }

        $testArguments = "t$passwordTestParams `"$tempArchivePath`""
        $testArgumentsForLog = "t$(if ($passwordTestParams) { ' -p***' } else { '' }) `"$tempArchivePath`""
        Write-Log "7-Zip перевірка: $ArcPath $testArgumentsForLog" -Level "DEBUG"

        $testProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $testProcessInfo.FileName = $ArcPath
        $testProcessInfo.Arguments = $testArguments
        $testProcessInfo.RedirectStandardOutput = $true
        $testProcessInfo.RedirectStandardError = $true
        $testProcessInfo.UseShellExecute = $false
        $testProcessInfo.CreateNoWindow = $true

        $testProcess = New-Object System.Diagnostics.Process
        $testProcess.StartInfo = $testProcessInfo
        $testProcess.Start() | Out-Null
        $testStdOut = $testProcess.StandardOutput.ReadToEnd()
        $testStdErr = $testProcess.StandardError.ReadToEnd()
        $testProcess.WaitForExit()

        Write-Log "7-Zip перевірка завершена з кодом: $($testProcess.ExitCode)" -Level "DEBUG"
        if (-not [string]::IsNullOrWhiteSpace($testStdOut)) { Write-Log "7-Zip перевірка STDOUT:`n$testStdOut" -Level "DEBUG" }
        if (-not [string]::IsNullOrWhiteSpace($testStdErr)) { Write-Log "7-Zip перевірка STDERR:`n$testStdErr" -Level "DEBUG" }

        if ($testProcess.ExitCode -ne 0) {
            Write-Host " ✘ $ArchiveName - архів не пройшов перевірку 7-Zip, тимчасовий файл видалено" -ForegroundColor Red
            Write-Log "Архів не пройшов перевірку 7-Zip: $ArchiveName. Код: $($testProcess.ExitCode). Тимчасовий файл буде видалено: $tempArchivePath" -Level "ERROR"
            Remove-SafeTempFile -Path $tempArchivePath
            return $false
        }

        Write-Log "Архів пройшов перевірку 7-Zip: $tempArchivePath" -Level "DEBUG"

        if (Test-Path -LiteralPath $finalArchivePath) {
            Write-Log "Фінальний архів уже існує і буде замінений після успішної перевірки: $finalArchivePath" -Level "WARNING"
            Remove-Item -LiteralPath $finalArchivePath -Force -ErrorAction Stop
        }

        Move-Item -LiteralPath $tempArchivePath -Destination $finalArchivePath -Force -ErrorAction Stop
        Write-Log "Архів перевірено та перенесено в основне сховище: $finalArchivePath" -Level "DEBUG"
        return $true
    } catch {
        Write-Host " ✘ $ArchiveName - помилка архівації" -ForegroundColor Red
        Write-Log ("Помилка архівації ${ArchiveName}: " + $_.Exception.Message) -Level "ERROR"
        if (Test-Path -LiteralPath $tempArchivePath -ErrorAction SilentlyContinue) {
            Write-Log "Видалення тимчасового архіву після помилки: $tempArchivePath" -Level "DEBUG"
            Remove-SafeTempFile -Path $tempArchivePath
        }
        return $false
    }
}

