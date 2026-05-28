# ==============================================================================
# BRAVO.ArchivLims.Network.ps1
# Автоматично винесені функції з BRAVO_ARCHIV_LIMS.ps1
# ==============================================================================

function Load-CredentialsFromManager {
    Write-Log "Облікові дані зберігаються в Windows Credential Manager" -Level "INFO"
    Write-Log "Підключення до мережевого диска буде виконано автоматично" -Level "INFO"
}

function Test-BravoDriveLetterAvailable {
    param([string]$DriveLetter)

    if ([string]::IsNullOrWhiteSpace($DriveLetter)) {
        return $false
    }

    $normalized = $DriveLetter.Trim().TrimEnd('\')
    if ($normalized -notmatch '^[A-Za-z]:$') {
        return $false
    }

    $driveName = $normalized.TrimEnd(':')
    $psDrive = Get-PSDrive -Name $driveName -ErrorAction SilentlyContinue
    if ($psDrive) {
        return $false
    }

    return -not (Test-Path -LiteralPath ($normalized + '\'))
}

function Get-BravoFreeNetworkDriveLetter {
    $preferredLetters = @($networkCopyConfig.PreferredDriveLetters) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    if (-not $preferredLetters -or $preferredLetters.Count -eq 0) {
        $preferredLetters = @("Z:", "Y:", "X:", "W:", "V:")
    }

    foreach ($letter in $preferredLetters) {
        $normalized = $letter.Trim().TrimEnd('\')
        if ($normalized -notmatch '^[A-Za-z]:$') {
            Write-Log "Пропущено некоректну літеру мережевого диска в конфігурації: $letter" -Level "WARNING"
            continue
        }

        if (Test-BravoDriveLetterAvailable -DriveLetter $normalized) {
            return $normalized
        }

        Write-Log "Літера $normalized вже зайнята. Скрипт її не відключає і шукає іншу." -Level "INFO"
    }

    return $null
}

function Connect-NetworkDrive {
    $networkPath = $networkCopyConfig.NetworkPath.TrimEnd('\')
    $networkTarget = $global:credentialTargets.Network
    $networkCredential = Get-WindowsCredential -Target $networkTarget
    $networkUsername = if ($networkCredential -and $networkCredential.Username) { $networkCredential.Username } else { $networkCopyConfig.Username }
    $networkPassword = if ($networkCredential) { $networkCredential.Password } else { $null }

    $global:BravoNetworkDriveLetter = $null
    $global:BravoNetworkDrivePath = $null
    $global:BravoNetworkDriveConnectedByScript = $false

    if ([string]::IsNullOrEmpty($networkUsername) -or [string]::IsNullOrEmpty($networkPassword)) {
        Write-Log "Мережеві облікові дані не знайдено в Windows Credential Manager (Target: $networkTarget)" -Level "ERROR"
        Write-Host "[!!] Мережеві облікові дані не знайдено в диспетчері облікових даних Windows. Запустіть -SetupCredentials." -ForegroundColor Red
        return $false
    }

    Write-Log "Підключення тимчасового мережевого диска..." -Level "INFO"
    Write-Log "Шлях: $networkPath" -Level "INFO"

    $maxRetries = if ($networkCopyConfig.MaxRetries) { $networkCopyConfig.MaxRetries } else { 3 }
    $retryDelay = if ($networkCopyConfig.RetryDelay) { $networkCopyConfig.RetryDelay } else { 5 }

    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        $driveLetter = Get-BravoFreeNetworkDriveLetter
        if ([string]::IsNullOrWhiteSpace($driveLetter)) {
            Write-Log "Не знайдено вільної літери для тимчасового мережевого диска. Перевірте Copy.Network.PreferredDriveLetters у BRAVO.config.ps1." -Level "ERROR"
            return $false
        }

        Write-Log "Спроба $attempt з $maxRetries. Використовується вільна літера $driveLetter" -Level "INFO"
        $result = net use $driveLetter "$networkPath" "$networkPassword" /user:$networkUsername /persistent:no 2>&1

        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath ($driveLetter + '\'))) {
            $global:BravoNetworkDriveLetter = $driveLetter
            $global:BravoNetworkDrivePath = $networkPath
            $global:BravoNetworkDriveConnectedByScript = $true
            $global:bazaPaths.Destination_Network = "$driveLetter\BAZA"

            $driveInfo = Get-PSDrive -Name $driveLetter.TrimEnd(':') -ErrorAction SilentlyContinue
            if ($driveInfo) {
                $freeSpaceGB = [string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F2}", ($driveInfo.Free / 1GB))
                Write-Log "[OK] Тимчасовий мережевий диск підключено як $driveLetter | Вільний простір: $freeSpaceGB GB" -Level "SUCCESS"
            } else {
                Write-Log "[OK] Тимчасовий мережевий диск підключено як $driveLetter" -Level "SUCCESS"
            }
            return $true
        }

        Write-Log "Не вдалося підключити мережевий диск $driveLetter. Відповідь: $result" -Level "WARNING"
        if ($attempt -lt $maxRetries) {
            Write-Log "Повтор через $retryDelay секунд..." -Level "WARNING"
            Start-Sleep -Seconds $retryDelay
        }
    }

    Write-Host "[!!] Не вдалося підключити тимчасовий мережевий диск після $maxRetries спроб" -ForegroundColor Red
    Write-Log "[!!] Не вдалося підключити тимчасовий мережевий диск після $maxRetries спроб" -Level "ERROR"
    Write-Host "Перевірте:" -ForegroundColor Yellow
    Write-Host "1. Чи доступний мережевий шлях: $networkPath" -ForegroundColor Gray
    Write-Host "2. Чи правильний пароль у диспетчері облікових даних Windows" -ForegroundColor Gray
    Write-Host "3. Чи є вільна літера у Copy.Network.PreferredDriveLetters" -ForegroundColor Gray
    Write-Host "4. Спробуйте оновити облікові дані: .\BRAVO_ARCHIV_LIMS.ps1 -SetupCredentials -ForceRecreate" -ForegroundColor Gray

    return $false
}

function Disconnect-NetworkDrive {
    $driveLetter = $global:BravoNetworkDriveLetter

    if (-not $global:BravoNetworkDriveConnectedByScript -or [string]::IsNullOrWhiteSpace($driveLetter)) {
        Write-Log "Тимчасовий мережевий диск цим запуском не підключався. Відключення пропущено." -Level "INFO"
        return $true
    }

    if (-not (Test-Path -LiteralPath ($driveLetter + '\'))) {
        Write-Log "Тимчасовий мережевий диск $driveLetter вже відсутній" -Level "INFO"
        return $true
    }

    $result = net use $driveLetter /delete /y 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Log "Тимчасовий мережевий диск $driveLetter відключено" -Level "SUCCESS"
        $global:BravoNetworkDriveLetter = $null
        $global:BravoNetworkDrivePath = $null
        $global:BravoNetworkDriveConnectedByScript = $false
        return $true
    }

    Write-Log "Помилка відключення тимчасового мережевого диска ${driveLetter}: $result" -Level "WARNING"
    return $false
}
function Copy-ToNetworkDrive {
    param(
        [string]$SourcePath,
        [string]$DestinationFolder
    )
    
    $fileName = Split-Path $SourcePath -Leaf
    $networkPath = $networkCopyConfig.NetworkPath.TrimEnd('\')
    $destPath = "$networkPath\$DestinationFolder"
    $destFile = Join-Path $destPath $fileName
    
    $isHash = $fileName -match "\.sha512$"
    
    $maxRetries = if ($networkCopyConfig.MaxRetries) { $networkCopyConfig.MaxRetries } else { 3 }
    $retryDelay = if ($networkCopyConfig.RetryDelay) { $networkCopyConfig.RetryDelay } else { 5 }
    
    for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
        try {
            if (-not (Test-Path $destPath)) {
                $null = New-Item -ItemType Directory -Path $destPath -Force -ErrorAction Stop
            }
            
            Copy-Item -Path $SourcePath -Destination $destFile -Force -ErrorAction Stop
            
            if (Test-Path $destFile) {
                if (-not $isHash) {
                    $sizeMB = [math]::Round((Get-Item $SourcePath).Length / 1MB, 1)
                    Write-Log "[OK] $DestinationFolder ($sizeMB MB)" -Level "SUCCESS"
                } else {
                    $sizeKB = [math]::Round((Get-Item $SourcePath).Length / 1KB, 1)
                    Write-Log "[OK] $DestinationFolder ($sizeKB KB)" -Level "SUCCESS"
                }
                return $true
            }
        } catch {
            if ($attempt -lt $maxRetries) {
                Write-Log "  Копіювання ${fileName}: спроба ${attempt} не вдалася. Повтор через ${retryDelay} сек..." -Level "WARNING"
                Start-Sleep -Seconds $retryDelay
            } else {
                Write-Log "[!!] $DestinationFolder - $($_.Exception.Message)" -Level "ERROR"
            }
        }
    }
    return $false
}

function Sync-Folders {
    param(
        [string]$SourcePath,
        [string]$DestinationPath,
        [string]$SyncType = "LOCAL"
    )
    
    if (-not (Test-Path $SourcePath)) {
        Write-Log "ДЖЕРЕЛЬНА ПАПКА НЕ ЗНАЙДЕНА: $SourcePath" -Level "ERROR"
        return $false
    }
    
    if ($SyncType -eq "NETWORK") {
        if ($DestinationPath -match "^\\\\") {
            $testPath = $DestinationPath
            if (-not (Test-Path $testPath)) {
                Write-Log "Мережевий шлях недоступний: $DestinationPath" -Level "ERROR"
                return $false
            }
        } else {
            $driveLetter = $DestinationPath.Substring(0, 2)
            if (-not (Test-Path $driveLetter)) {
                Write-Log "Мережевий диск $driveLetter не пiдключено" -Level "ERROR"
                return $false
            }
        }
    }
    
    if ($SyncType -eq "LOCAL" -and -not (Test-Path $DestinationPath)) {
        try {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        } catch {
            Write-Log "Не вдалося створити цiльову папку: $($_.Exception.Message)" -Level "ERROR"
            return $false
        }
    }
    
    $robocopyParams = @(
        "`"$SourcePath`"", "`"$DestinationPath`"",
        "/E", "/COPY:DAT", "/DCOPY:T", "/FFT", "/DST", "/XO", "/XJ", "/Z", "/TBD", "/NP", "/MT:8",
        "/UNICODE", "/NDL", "/NS", "/NC"
    )
    
    if ($SyncType -eq "NETWORK") {
        $robocopyParams += @("/R:5", "/W:10")
    } else {
        $robocopyParams += @("/R:3", "/W:5")
    }
    
    try {
        $process = Start-Process robocopy.exe -ArgumentList $robocopyParams -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop
        $exitCode = $process.ExitCode
        
        return ($exitCode -le 7)
    } catch {
        Write-Log "КРИТИЧНА ПОМИЛКА: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
}
