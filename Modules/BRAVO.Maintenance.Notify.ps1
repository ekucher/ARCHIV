# ==============================================================================
# BRAVO.Maintenance.Notify.ps1
# Автоматично винесені функції з BRAVO_MAINTENANCE.ps1
# ==============================================================================

function Send-SlackAlert {
    param(
        [string]$Message,
        [switch]$IsCritical
    )
    
    if ($script:SlackMode -eq "none") {
        return
    }
    
    $isSpaceError = $Message -match "Недостатньо вільного місця|не вистачає місця"
    
    if ($IsCritical -or $isSpaceError) {
        $global:CriticalErrors = $true
        $global:criticalErrorOccurred = $true
        
        if ($script:SlackMode -eq "errors_only" -or $script:SlackMode -eq "all") {
            if ([string]::IsNullOrWhiteSpace($SlackWebhookUrl)) {
                Write-MaintenanceLog "Slack webhook не налаштовано. Відправку пропущено." -Level "WARNING"
                return
            }

            $slackBody = @{ text = $Message }
            
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
                
                Write-MaintenanceLog "Критичне повідомлення відправлено в Slack" -Level "INFO"
            }
            catch {
                Write-ErrorLog "Помилка відправки Slack: $($_.Exception.Message)"
            }
        }
    }
    else {
        if ($script:SlackMode -ne "all") {
            return
        }
        $global:SlackMessageBuffer.Add($Message)
    }
}

function Send-FinalReport {
    param($LOG_FILE)
    
    if ($script:SlackMode -eq "none") {
        return
    }
    
    $currentTime = Get-Date
    $elapsedTime = $currentTime - $global:ScriptStartTime
    $datePart = $currentTime.ToString('dd MMMM yyyy')
    $timePart = $currentTime.ToString('HH:mm:ss')
    $durationText = Format-Duration $elapsedTime
    
    $slackMsg = ""
    $shouldSend = $false
    
    $hasErrors = ($global:CriticalErrorsList.Count -gt 0)
    
    if ($hasErrors) {
        $uniqueErrors = $global:CriticalErrorsList | Select-Object -Unique
        $errorDetails = $uniqueErrors -join "`n• "
        $errorDetails = "• " + $errorDetails
        
        # Збираємо деталі з різних джерел
        $allDetails = @()
        
        # Деталі архівів
        if ($global:BackupArchiveDetails) {
            $allDetails += $global:BackupArchiveDetails
        }
        
        # Деталі дисків
        if ($global:DiskSpaceDetails) {
            $allDetails += $global:DiskSpaceDetails
        }
        
        $detailsText = $allDetails -join "`n"
        
        $slackMsg = @"
:rotating_light: **ВИЯВЛЕНІ КРИТИЧНІ ПОМИЛКИ**
:derelict_house_building: Установа: $($global:ObjectName)
:spiral_calendar_pad: Дата: $datePart
:alarm_clock: Час: $timePart
:hourglass_flowing_sand: Тривалість: $durationText

:x: **Виявлені проблеми:**
$errorDetails

$detailsText

:page_with_curl: Лог: $LOG_FILE
"@
        $shouldSend = $true
    } 
    else {
        if ($script:SlackMode -eq "all") {
            $slackMsg = @"
:white_check_mark: **СКРИПТ УСПІШНО ВИКОНАНО**
:derelict_house_building: Установа: $($global:ObjectName)
:spiral_calendar_pad: Дата: $datePart
:alarm_clock: Час: $timePart
:hourglass_flowing_sand: Тривалість: $durationText

:page_with_curl: Лог: $LOG_FILE
"@
            $shouldSend = $true
        } else {
            return
        }
    }
    
    if (-not $shouldSend) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($SlackWebhookUrl)) {
        try {
            if ($global:LOG_FILE) {
                "Slack webhook не налаштовано. Фінальне повідомлення не відправлено." | Out-File -FilePath $global:LOG_FILE -Append -Encoding UTF8
            }
        } catch { }
        return
    }

    try {
        $slackBody = @{ text = $slackMsg }
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
        
        try {
            if ($global:LOG_FILE) {
                "Slack: фінальне повідомлення відправлено" | Out-File -FilePath $global:LOG_FILE -Append -Encoding UTF8
            }
        } catch { }
    }
    catch {
        Write-ErrorLog "Помилка відправки фінального повідомлення: $($_.Exception.Message)"
    }
}
