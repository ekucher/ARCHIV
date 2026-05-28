# ==============================================================================
# BRAVO.ArchivLims.Sftp.ps1
# Автоматично винесені функції з BRAVO_ARCHIV_LIMS.ps1
# ==============================================================================

function Escape-WinSCPScriptValue {
    param([string]$Value)

    if ($null -eq $Value) { return "" }
    return $Value.Replace('"', '""')
}

function New-WinSCPEnsureDirectoryScript {
    param([string]$RemotePath)

    $normalizedPath = $RemotePath.Replace('\', '/').Trim('/')
    if ([string]::IsNullOrEmpty($normalizedPath)) {
        return "cd /"
    }

    $commands = New-Object System.Collections.Generic.List[string]
    $commands.Add("cd /")

    foreach ($segment in $normalizedPath.Split('/')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { continue }
        $safeSegment = Escape-WinSCPScriptValue -Value $segment
        $commands.Add("option batch continue")
        $commands.Add("mkdir `"$safeSegment`"")
        $commands.Add("option batch abort")
        $commands.Add("cd `"$safeSegment`"")
    }

    return ($commands -join "`r`n")
}

function Test-SFTPConnection {
    if (-not $winSCPPath) {
        Write-Log "WinSCP не знайдено. SFTP недоступний" -Level "ERROR"
        return $false
    }
    
    if (-not $global:sftpConfig.Enabled) {
        Write-Log "SFTP вимкнено в конфігурації" -Level "INFO"
        return $false
    }
    
    if ([string]::IsNullOrEmpty($global:sftpConfig.Server)) {
        Write-Log "SFTP сервер не вказано в конфігурації" -Level "ERROR"
        return $false
    }

    if ([string]::IsNullOrEmpty($global:sftpConfig.HostKey)) {
        Write-Log "SFTP host key не вказано в конфігурації" -Level "ERROR"
        return $false
    }

    $sftpTarget = $global:credentialTargets.SFTP
    $sftpCredential = Get-WindowsCredential -Target $sftpTarget

    if (-not $sftpCredential -or [string]::IsNullOrEmpty($sftpCredential.Username) -or [string]::IsNullOrEmpty($sftpCredential.Password)) {
        Write-Log "SFTP облікові дані не знайдено в Windows Credential Manager (Target: $sftpTarget)" -Level "ERROR"
        return $false
    }

    $global:sftpConfig.Username = $sftpCredential.Username
    
    return $true
}

function Upload-ToSFTP {
    param(
        [string]$LocalFilePath,
        [string]$RemoteSubPath,
        [string]$DisplayName
    )
    
    if (-not (Test-SFTPConnection)) {
        return $false
    }
    
    if (-not (Test-Path $LocalFilePath)) {
        Write-Log "Файл не знайдено: $LocalFilePath" -Level "ERROR"
        return $false
    }
    
    $fileName = Split-Path $LocalFilePath -Leaf
    $remotePath = $global:sftpConfig.RemotePath.TrimEnd('/') + "/" + $RemoteSubPath.TrimStart('/')
    $sftpTarget = $global:credentialTargets.SFTP
    $sftpCredential = Get-WindowsCredential -Target $sftpTarget
    if (-not $sftpCredential) {
        Write-Log "SFTP облікові дані не знайдено в Windows Credential Manager (Target: $sftpTarget)" -Level "ERROR"
        return $false
    }

    $sftpUsername = Escape-WinSCPScriptValue -Value $sftpCredential.Username
    $sftpPassword = Escape-WinSCPScriptValue -Value $sftpCredential.Password
    $sftpServer = Escape-WinSCPScriptValue -Value $global:sftpConfig.Server
    $sftpHostKey = Escape-WinSCPScriptValue -Value $global:sftpConfig.HostKey
    $sftpPort = $global:sftpConfig.Port
    $sftpTimeout = if ($global:sftpConfig.Timeout) { $global:sftpConfig.Timeout } else { 30 }
    $sftpOpenUrl = Escape-WinSCPScriptValue -Value "sftp://$($global:sftpConfig.Server):$sftpPort/"
    $ensureRemotePathScript = New-WinSCPEnsureDirectoryScript -RemotePath $remotePath
    $localFilePathEscaped = Escape-WinSCPScriptValue -Value $LocalFilePath
    
    # Пароль береться тільки з Windows Credential Manager.
    $scriptContent = @"
option batch abort
option confirm off
open "$sftpOpenUrl" -username="$sftpUsername" -password="$sftpPassword" -hostkey="$sftpHostKey" -timeout=$sftpTimeout
$ensureRemotePathScript
put "$localFilePathEscaped"
exit
"@
    
    $scriptFile = New-SafeTempFilePath -Prefix "winscp_script" -Extension ".txt"
    try {
        $scriptContent | Out-File -LiteralPath $scriptFile -Encoding ASCII -ErrorAction Stop
    } catch {
        Write-Host "  ✘ $DisplayName - не вдалося створити тимчасовий файл WinSCP" -ForegroundColor Red
        Write-Log "SFTP помилка створення тимчасового файла WinSCP: $($_.Exception.Message)" -Level "ERROR"
        return $false
    }
    
    $fileSizeMB = Format-SizeMB -SizeMB ([math]::Round((Get-Item $LocalFilePath).Length / 1MB, 1)) -Width 0
    Write-Log "SFTP завантаження: $fileName ($fileSizeMB)" -Level "INFO"
    
    $winscpLogFile = New-SafeTempFilePath -Prefix "winscp_upload" -Extension ".log"
    $winscpOutFile = New-SafeTempFilePath -Prefix "winscp_upload_out" -Extension ".txt"
    $winscpErrFile = New-SafeTempFilePath -Prefix "winscp_upload_err" -Extension ".txt"
    $process = Start-Process -FilePath $winSCPPath -ArgumentList @("/script=`"$scriptFile`"", "/log=`"$winscpLogFile`"") -Wait -NoNewWindow -PassThru -RedirectStandardOutput $winscpOutFile -RedirectStandardError $winscpErrFile
    
    # Очищення
    Remove-SafeTempFile -Path $scriptFile
    Remove-SafeTempFile -Path $winscpOutFile
    Remove-SafeTempFile -Path $winscpErrFile
    
    if ($process.ExitCode -eq 0) {
        Write-Log "SFTP успішно: $fileName" -Level "SUCCESS"
        Remove-SafeTempFile -Path $winscpLogFile
        return $true
    } else {
        Write-Host " ✘ ${DisplayName}: помилка SFTP (код $($process.ExitCode))" -ForegroundColor Red
        Write-Log "SFTP помилка (код $($process.ExitCode)): $fileName" -Level "ERROR"
        Write-Log "SFTP лог WinSCP: $winscpLogFile" -Level "ERROR"
        return $false
    }
}
