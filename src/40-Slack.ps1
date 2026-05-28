# ==================================================================================================
# BRAVO Slack / TLS Notifications
# ==================================================================================================

function Set-BravoTlsProtocol {
    try {
        $protocols = [Net.SecurityProtocolType]::Tls12

        if ([Enum]::GetNames([Net.SecurityProtocolType]) -contains "Tls13") {
            $protocols = $protocols -bor [Net.SecurityProtocolType]::Tls13
        }

        [Net.ServicePointManager]::SecurityProtocol = $protocols
        [Net.ServicePointManager]::Expect100Continue = $false
    }
    catch {
        Set-BravoTlsProtocol
    }
}

function Invoke-BravoSlackWebhook {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [int]$TimeoutSec = 30
    )

    if ([string]::IsNullOrWhiteSpace($SlackWebhookUrl)) {
        throw "SlackWebhookUrl is empty"
    }

    Set-BravoTlsProtocol

    $slackBody = @{
        text = $Message
    }

    $jsonBody = $slackBody | ConvertTo-Json -Depth 10 -Compress

    try {
        Invoke-RestMethod `
            -Uri $SlackWebhookUrl `
            -Method Post `
            -Body $jsonBody `
            -ContentType "application/json; charset=utf-8" `
            -TimeoutSec $TimeoutSec `
            -ErrorAction Stop | Out-Null
    }
    catch {
        $errorMessage = $_.Exception.Message

        if ($_.Exception.InnerException) {
            $errorMessage += " | InnerException: $($_.Exception.InnerException.Message)"
        }

        if ($_.ErrorDetails) {
            $errorMessage += " | Response: $($_.ErrorDetails)"
        }

        throw "Slack webhook POST failed: $errorMessage"
    }
}

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
                try {
                    Invoke-BravoSlackWebhook -Message $Message
                    Write-Log "Критичне повідомлення (помилки місця) відправлено в Slack" -Level "INFO"
                }
                catch {
                    Write-Log "ПОМИЛКА негайної відправки в Slack: $($_.Exception.Message)" -Level "ERROR"
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
        Invoke-BravoSlackWebhook -Message $slackMsg
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

function Send-BravoHealthSlackMessage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if ($script:SlackMode -eq "none") {
        Write-Log -Message "Health-check Slack message skipped because Slack mode is none." -Level "DEBUG"
        return
    }

    if ([string]::IsNullOrWhiteSpace($SlackWebhookUrl)) {
        Write-Log -Message "Health-check Slack message skipped because SlackWebhookUrl is empty." -Level "WARNING"
        return
    }

    try {
        if (Get-Command Invoke-BravoSlackWebhook -ErrorAction SilentlyContinue) {
            Invoke-BravoSlackWebhook -Message $Message
        }
        else {
            Send-SlackAlert -Message $Message -IsCritical
        }

        Write-Log -Message "Health-check повідомлення відправлено в Slack" -Level "SUCCESS"
    }
    catch {
        Write-Log -Message "ПОМИЛКА відправки health-check повідомлення в Slack: $($_.Exception.Message)" -Level "ERROR"
    }
}