# ==================================================================================================
# BRAVO System / Runtime Helpers
# ==================================================================================================

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

function Test-BravoInteractiveConsole {
    param([string]$TaskUserName)

    if (-not [Environment]::UserInteractive) {
        return $false
    }

    if ($env:SESSIONNAME -and $env:SESSIONNAME -ieq "Services") {
        return $false
    }

    if ($Host.Name -eq "ServerRemoteHost") {
        return $false
    }

    try {
        if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
            return $false
        }
    }
    catch {
        # Some hosts do not expose console redirection state reliably.
    }

    if (-not [string]::IsNullOrWhiteSpace($TaskUserName)) {
        try {
            $currentName = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $currentLeaf = ($currentName -split "\\")[-1]
            $taskLeaf = ($TaskUserName -split "\\")[-1]

            if ($currentLeaf -ieq $taskLeaf) {
                return $false
            }
        }
        catch {
            # Do not block execution if identity detection fails.
        }
    }

    return $true
}

function Wait-BravoInteractiveExit {
    param(
        [string]$TaskUserName,
        [int]$ExitCode = 0
    )

    if (-not (Test-BravoInteractiveConsole -TaskUserName $TaskUserName)) {
        return
    }

    try {
        Write-Host ""
        Write-Host "Натисніть будь-яку клавішу для завершення..." -ForegroundColor Yellow
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    }
    catch {
        try {
            [void](Read-Host "Натисніть Enter для завершення")
        }
        catch {
            # Never block scheduler/non-console runs because of pause handling.
        }
    }
}
