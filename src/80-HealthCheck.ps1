# ==================================================================================================
# BRAVO Health Check
# ==================================================================================================

function Format-BravoDecimal {
    param(
        [double]$Value,
        [int]$Digits = 2
    )

    return ([math]::Round($Value, $Digits)).ToString("N$Digits", [Globalization.CultureInfo]::GetCultureInfo("uk-UA"))
}

function Format-BravoFileSize {
    param([int64]$Bytes)

    if ($Bytes -ge 1GB) {
        return "$(Format-BravoDecimal -Value ($Bytes / 1GB) -Digits 2) GB"
    }

    if ($Bytes -ge 1MB) {
        return "$(Format-BravoDecimal -Value ($Bytes / 1MB) -Digits 2) МБ"
    }

    if ($Bytes -ge 1KB) {
        return "$(Format-BravoDecimal -Value ($Bytes / 1KB) -Digits 2) КБ"
    }

    return "$Bytes байт"
}

function Expand-BravoHealthToken {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    $expanded = [string]$Value
    $expanded = $expanded.Replace("{ArchivePrefix}", [string]$ArchivePrefix)
    $expanded = $expanded.Replace("{ROOT_LIMS}", [string]$ROOT_LIMS)
    $expanded = $expanded.Replace("{ARC_DIR}", [string]$ARC_DIR)
    $expanded = $expanded.Replace("{LOG_DIR}", [string]$LOG_DIR)
    $expanded = $expanded.Replace("{TRACE_DIR}", [string]$TRACE_DIR)
    $expanded = $expanded.Replace("{EXCHANGAPI_ARCHIV_DIR}", [string]$EXCHANGAPI_ARCHIV_DIR)

    if (Get-Command -Name [Environment]::ExpandEnvironmentVariables -ErrorAction SilentlyContinue) {
        $expanded = [Environment]::ExpandEnvironmentVariables($expanded)
    }

    return $expanded
}

function Get-BravoHealthArchiveCategories {
    $configured = Get-BravoConfigValue -Name "HealthCheckArchiveCategories" -Default $null

    if ($configured) {
        return @($configured)
    }

    return @(
        @{
            Name = "LIMS"
            Path = "{ARC_DIR}"
            Pattern = "{ArchivePrefix}_*.mdz"
            Exclude = @(
                "{ArchivePrefix}_blog_*.mdz",
                "{ArchivePrefix}_bravoexch_*.mdz",
                "{ArchivePrefix}_before_*.mdz",
                "{ArchivePrefix}_after_*.mdz"
            )
        },
        @{
            Name = "BLOG"
            Path = "{ARC_DIR}"
            Pattern = "{ArchivePrefix}_blog_*.mdz"
            Exclude = @()
        },
        @{
            Name = "BRAVOEXCH"
            Path = "{ARC_DIR}"
            Pattern = "{ArchivePrefix}_bravoexch_*.mdz"
            Exclude = @()
        }
    )
}

function Test-BravoArchiveSha512 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ArchivePath
    )

    $shaPath = "$ArchivePath.sha512"

    if (-not (Test-Path -LiteralPath $shaPath)) {
        return [PSCustomObject]@{
            Status = "Missing"
            Text = ":warning: Відсутній"
            Details = "SHA512 file not found: $shaPath"
        }
    }

    try {
        $shaText = Get-Content -LiteralPath $shaPath -Raw -ErrorAction Stop
        $expectedHash = $null

        if ($shaText -match '(?im)\b([A-Fa-f0-9]{128})\b') {
            $expectedHash = $Matches[1].ToUpperInvariant()
        }

        if ([string]::IsNullOrWhiteSpace($expectedHash)) {
            return [PSCustomObject]@{
                Status = "Invalid"
                Text = ":x: Некоректний файл SHA512"
                Details = "SHA512 hash was not found in: $shaPath"
            }
        }

        $actualHash = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA512 -ErrorAction Stop).Hash.ToUpperInvariant()

        if ($actualHash -eq $expectedHash) {
            return [PSCustomObject]@{
                Status = "Valid"
                Text = ":white_check_mark: Валідний"
                Details = ""
            }
        }

        return [PSCustomObject]@{
            Status = "Invalid"
            Text = ":x: НЕВАЛІДНИЙ"
            Details = "SHA512 mismatch for $ArchivePath"
        }
    }
    catch {
        return [PSCustomObject]@{
            Status = "Error"
            Text = ":x: Помилка перевірки"
            Details = $_.Exception.Message
        }
    }
}

function Get-BravoLatestHealthArchive {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Category
    )

    $name = [string]$Category.Name
    $path = Expand-BravoHealthToken -Value ([string]$Category.Path)
    $pattern = Expand-BravoHealthToken -Value ([string]$Category.Pattern)

    $excludePatterns = @()
    if ($Category.ContainsKey("Exclude") -and $Category.Exclude) {
        $excludePatterns = @($Category.Exclude) | ForEach-Object { Expand-BravoHealthToken -Value ([string]$_) }
    }

    if ([string]::IsNullOrWhiteSpace($path)) {
        $path = $ARC_DIR
    }

    if ([string]::IsNullOrWhiteSpace($pattern)) {
        $pattern = "*.mdz"
    }

    if (-not (Test-Path -LiteralPath $path)) {
        return [PSCustomObject]@{
            Category = $name
            Path = $path
            Pattern = $pattern
            Archive = $null
            Error = "archive directory not found"
        }
    }

    $files = @(Get-ChildItem -Path $path -Filter $pattern -File -ErrorAction SilentlyContinue)

    if ($excludePatterns.Count -gt 0) {
        foreach ($excludePattern in $excludePatterns) {
            $files = @($files | Where-Object { $_.Name -notlike $excludePattern })
        }
    }

    $latest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1

    return [PSCustomObject]@{
        Category = $name
        Path = $path
        Pattern = $pattern
        Archive = $latest
        Error = ""
    }
}

function New-BravoHealthCheckResult {
    param(
        [bool]$HasCriticalIssues,
        [string]$Message,
        [object[]]$Problems = @(),
        [object[]]$Archives = @()
    )

    $result = New-Object PSObject
    $result | Add-Member -MemberType NoteProperty -Name "HasCriticalIssues" -Value $HasCriticalIssues
    $result | Add-Member -MemberType NoteProperty -Name "Message" -Value $Message
    $result | Add-Member -MemberType NoteProperty -Name "Problems" -Value @($Problems)
    $result | Add-Member -MemberType NoteProperty -Name "Archives" -Value @($Archives)

    return $result
}

function Invoke-BravoHealthCheck {
    param(
        [switch]$SendSlack = $true
    )

    $enabled = ConvertTo-BravoNormalizedSwitch `
        -Value (Get-BravoConfigValue -Name "HealthCheckEnabled" -Default "on") `
        -Default "on"

    if ($enabled -eq "off") {
        Write-Log -Message "Health-check: вимкнено в конфігурації" -Level "DEBUG"
        return New-BravoHealthCheckResult `
            -HasCriticalIssues $false `
            -Message "" `
            -Problems @() `
            -Archives @()
    }

    $maxAgeHours = [double](Get-BravoConfigValue -Name "HealthCheckArchiveMaxAgeHours" -Default 2)
    $minFreeSpaceGB = [double](Get-BravoConfigValue -Name "HealthCheckMinFreeSpaceGB" -Default $MIN_FREE_SPACE)
    $drives = @(Get-BravoConfigValue -Name "HealthCheckDrives" -Default @())

    if (-not $drives -or $drives.Count -eq 0) {
        $rootDrive = [System.IO.Path]::GetPathRoot($ROOT_LIMS)
        $drives = @($rootDrive)
    }

    $nowCheck = Get-Date
    $elapsedTime = $nowCheck - $global:ScriptStartTime
    $datePart = $nowCheck.ToString('dd MMMM yyyy', [Globalization.CultureInfo]::GetCultureInfo("uk-UA"))
    $timePart = $nowCheck.ToString('HH:mm:ss')
    $durationText = Format-Duration $elapsedTime

    $problems = New-Object System.Collections.Generic.List[string]
    $archiveDetails = New-Object System.Collections.Generic.List[object]

    Write-Log -Message "==="
    Write-Log -Message "=== HEALTH-CHECK: ДИСКИ ТА АКТУАЛЬНІСТЬ АРХІВІВ ==="

    foreach ($drive in $drives) {
        $driveText = [string]$drive
        if ([string]::IsNullOrWhiteSpace($driveText)) {
            continue
        }

        $driveRoot = $driveText
        if ($driveRoot -match '^[A-Za-z]:$') {
            $driveRoot = "$driveRoot\"
        }

        try {
            $driveInfo = New-Object System.IO.DriveInfo($driveRoot)

            if (-not $driveInfo.IsReady) {
                $problems.Add("• $($driveInfo.Name.TrimEnd('\')): диск не готовий")
                Write-Log -Message "Health-check: диск $($driveInfo.Name) не готовий" -Level "ERROR"
                continue
            }

            $freeGb = [math]::Round($driveInfo.AvailableFreeSpace / 1GB, 2)

            if ($freeGb -lt $minFreeSpaceGB) {
                $problems.Add("• $($driveInfo.Name.TrimEnd('\')): критично мало вільного місця ($(Format-BravoDecimal -Value $freeGb -Digits 2) GB, мінімум $(Format-BravoDecimal -Value $minFreeSpaceGB -Digits 0) GB)")
                Write-Log -Message "Health-check: $($driveInfo.Name) критично мало вільного місця: $freeGb GB" -Level "ERROR"
            }
            else {
                Write-Log -Message "Health-check: $($driveInfo.Name) вільне місце OK: $freeGb GB" -Level "INFO"
            }
        }
        catch {
            $problems.Add("• ${driveText}: помилка перевірки диска ($($_.Exception.Message))")
            Write-Log -Message "Health-check: помилка перевірки диска ${driveText}: $($_.Exception.Message)" -Level "ERROR"
        }
    }

    foreach ($category in Get-BravoHealthArchiveCategories) {
        $latestInfo = Get-BravoLatestHealthArchive -Category $category
        $categoryName = [string]$latestInfo.Category

        if ($latestInfo.Error) {
            $problems.Add("• ${categoryName}: $($latestInfo.Error) ($($latestInfo.Path))")
            $archiveDetails.Add([PSCustomObject]@{
                Category = $categoryName
                Text = "• ${categoryName}: архів не перевірено — $($latestInfo.Error) ($($latestInfo.Path))"
                IsProblem = $true
            })
            Write-Log -Message "Health-check: ${categoryName}: $($latestInfo.Error)" -Level "ERROR"
            continue
        }

        if (-not $latestInfo.Archive) {
            $problems.Add("• ${categoryName}: архів не знайдено (патерн: $($latestInfo.Pattern))")
            $archiveDetails.Add([PSCustomObject]@{
                Category = $categoryName
                Text = "• ${categoryName}: архів не знайдено`n  └ :mag: Патерн: $($latestInfo.Pattern)"
                IsProblem = $true
            })
            Write-Log -Message "Health-check: ${categoryName}: архів не знайдено" -Level "ERROR"
            continue
        }

        $file = $latestInfo.Archive
        $ageHours = [math]::Round(((Get-Date) - $file.CreationTime).TotalHours, 1)
        $isStale = ($ageHours -gt $maxAgeHours)
        $shaResult = Test-BravoArchiveSha512 -ArchivePath $file.FullName
        $sizeText = Format-BravoFileSize -Bytes $file.Length

        if ($isStale) {
            $problems.Add("• ${categoryName}: архів застарів (вік $(Format-BravoDecimal -Value $ageHours -Digits 1) год, ліміт $(Format-BravoDecimal -Value $maxAgeHours -Digits 0) год)")
        }

        if ($shaResult.Status -ne "Valid") {
            $problems.Add("• ${categoryName}: SHA512 $($shaResult.Text)")
        }

        $statusText = if ($isStale) { ":x: ЗАСТАРІВ" } else { ":white_check_mark: АКТУАЛЬНИЙ" }

        $archiveText = "• ${categoryName}: $($file.Name)`n" +
            "  └ :date: Створено: $($file.CreationTime.ToString('yyyy-MM-dd HH:mm:ss'))`n" +
            "  └ :stopwatch: Вік: $(Format-BravoDecimal -Value $ageHours -Digits 1) год (ліміт: $(Format-BravoDecimal -Value $maxAgeHours -Digits 0) год) → $statusText`n" +
            "  └ :floppy_disk: Розмір: $sizeText`n" +
            "  └ :closed_lock_with_key: SHA512: $($shaResult.Text)"

        $archiveDetails.Add([PSCustomObject]@{
            Category = $categoryName
            Text = $archiveText
            IsProblem = ($isStale -or $shaResult.Status -ne "Valid")
        })

        if ($isStale -or $shaResult.Status -ne "Valid") {
            Write-Log -Message "Health-check: ${categoryName}: проблема з архівом $($file.Name)" -Level "ERROR"
            if ($shaResult.Details) {
                Write-Log -Message "Health-check: ${categoryName}: $($shaResult.Details)" -Level "ERROR"
            }
        }
        else {
            Write-Log -Message "Health-check: ${categoryName}: архів актуальний і SHA512 валідний ($($file.Name))" -Level "SUCCESS"
        }
    }

    $hasCriticalIssues = ($problems.Count -gt 0)

    if ($hasCriticalIssues) {
        $message = ":rotating_light: **ВИЯВЛЕНІ КРИТИЧНІ ПОМИЛКИ**`n" +
            ":derelict_house_building: Установа: $($global:ObjectName)`n" +
            ":spiral_calendar_pad: Дата: $datePart`n" +
            ":alarm_clock: Час: $timePart`n" +
            ":hourglass_flowing_sand: Тривалість: $durationText`n`n" +
            ":x: **Виявлені проблеми:**`n" +
            (($problems | ForEach-Object { [string]$_ }) -join "`n") +
            "`n`n" +
            (($archiveDetails | ForEach-Object { [string]$_.Text }) -join "`n`n")

        $global:CriticalErrors = $true
        $global:criticalErrorOccurred = $true

        if ($SendSlack) {
            Send-BravoHealthSlackMessage -Message $message
        }
    }
    else {
        $message = ":white_check_mark: **HEALTH-CHECK OK**`n" +
            ":derelict_house_building: Установа: $($global:ObjectName)`n" +
            ":spiral_calendar_pad: Дата: $datePart`n" +
            ":alarm_clock: Час: $timePart`n" +
            ":hourglass_flowing_sand: Тривалість: $durationText`n`n" +
            (($archiveDetails | ForEach-Object { [string]$_.Text }) -join "`n`n")

        Write-Log -Message "Health-check: критичних проблем не виявлено" -Level "SUCCESS"

        if ($SendSlack -and $script:SlackMode -eq "all") {
            Send-BravoHealthSlackMessage -Message $message
        }
    }

    $problemArray = @()
    foreach ($problem in $problems) {
        if ($null -ne $problem) {
            $problemArray += [string]$problem
        }
    }

    $archiveArray = @()
    foreach ($archiveItem in $archiveDetails) {
        if ($null -ne $archiveItem) {
            $archiveArray += $archiveItem
        }
    }

    return New-BravoHealthCheckResult `
        -HasCriticalIssues ([bool]$hasCriticalIssues) `
        -Message ([string]$message) `
        -Problems $problemArray `
        -Archives $archiveArray
}