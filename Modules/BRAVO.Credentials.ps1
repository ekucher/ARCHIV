# ==============================================================================
# BRAVO.Credentials.ps1
# Спільні функції роботи з Windows Credential Manager.
# ==============================================================================

function Initialize-CredentialReader {
    if ("CredentialManager.NativeMethods" -as [type]) {
        return
    }

    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

namespace CredentialManager {
    public static class NativeMethods {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        public struct CREDENTIAL {
            public UInt32 Flags;
            public UInt32 Type;
            public string TargetName;
            public string Comment;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
            public UInt32 CredentialBlobSize;
            public IntPtr CredentialBlob;
            public UInt32 Persist;
            public UInt32 AttributeCount;
            public IntPtr Attributes;
            public string TargetAlias;
            public string UserName;
        }

        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern bool CredRead(string target, UInt32 type, UInt32 reservedFlag, out IntPtr credentialPtr);

        [DllImport("advapi32.dll", SetLastError = true)]
        public static extern void CredFree(IntPtr buffer);
    }
}
"@
}

function Get-WindowsCredential {
    param([string]$Target)

    Initialize-CredentialReader

    foreach ($type in @(1, 2)) {
        $credentialPtr = [IntPtr]::Zero
        try {
            $found = [CredentialManager.NativeMethods]::CredRead($Target, [uint32]$type, 0, [ref]$credentialPtr)
            if (-not $found -or $credentialPtr -eq [IntPtr]::Zero) {
                continue
            }

            $credential = [Runtime.InteropServices.Marshal]::PtrToStructure(
                $credentialPtr,
                [type][CredentialManager.NativeMethods+CREDENTIAL]
            )

            $password = ""
            if ($credential.CredentialBlob -ne [IntPtr]::Zero -and $credential.CredentialBlobSize -gt 0) {
                $password = [Runtime.InteropServices.Marshal]::PtrToStringUni(
                    $credential.CredentialBlob,
                    [int]($credential.CredentialBlobSize / 2)
                )
            }

            return [PSCustomObject]@{
                Target   = $Target
                Username = $credential.UserName
                Password = $password
                Type     = $type
            }
        } finally {
            if ($credentialPtr -ne [IntPtr]::Zero) {
                [CredentialManager.NativeMethods]::CredFree($credentialPtr)
            }
        }
    }

    return $null
}

function Save-WindowsCredential {
    param(
        [string]$Target,
        [PSCredential]$Credential
    )

    try {
        $username = $Credential.UserName
        $password = $Credential.GetNetworkCredential().Password

        cmdkey /delete:$Target 2>&1 | Out-Null
        $result = cmdkey /generic:$Target /user:$username /pass:$password 2>&1

        if ($LASTEXITCODE -eq 0) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Облікові дані збережено в Windows Credential Manager (Target: $Target)" -Level "SUCCESS"
            }
            return $true
        }

        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Помилка збереження облікових даних: $result" -Level "ERROR"
        }
        return $false
    } catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Помилка: $($_.Exception.Message)" -Level "ERROR"
        }
        return $false
    }
}

function Save-SecretToCredentialManager {
    param(
        [string]$Target,
        [string]$Username,
        [string]$Secret
    )

    try {
        cmdkey /delete:$Target 2>&1 | Out-Null
        cmdkey /generic:$Target /user:$Username /pass:$Secret 2>&1 | Out-Null
        return ($LASTEXITCODE -eq 0)
    } catch {
        return $false
    }
}

function Test-WindowsCredential {
    param([string]$Target)

    $output = cmdkey /list:$Target 2>&1
    return ($output -match "user:")
}

function Remove-WindowsCredential {
    param([string]$Target)

    try {
        cmdkey /delete:$Target 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
                Write-Log "Облікові дані видалено з Windows Credential Manager" -Level "SUCCESS"
            }
            return $true
        }
    } catch {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Помилка видалення облікових даних: $($_.Exception.Message)" -Level "WARNING"
        }
    }
    return $false
}

function Get-WindowsCredentialUsername {
    param([string]$Target)

    $output = cmdkey /list:$Target 2>&1
    if ($output -match "user:(\S+)") {
        return $matches[1]
    }
    return $null
}

function Get-WindowsCredentialPassword {
    param([string]$Target)

    $credential = Get-WindowsCredential -Target $Target
    if ($credential -and -not [string]::IsNullOrEmpty($credential.Password)) {
        return $credential.Password
    }

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log "Не вдалося отримати пароль із Windows Credential Manager (Target: $Target)" -Level "WARNING"
    }
    return $null
}

function Ensure-WindowsCredential {
    param(
        [string]$Target,
        [string]$PromptTitle,
        [string]$PromptDetails,
        [string]$DefaultUsername,
        [switch]$ForceRecreate
    )

    if ($ForceRecreate) {
        Remove-WindowsCredential -Target $Target | Out-Null
    }

    $credential = Get-WindowsCredential -Target $Target
    if ($credential -and -not [string]::IsNullOrWhiteSpace($credential.Password)) {
        if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
            Write-Log "Облікові дані знайдено в Windows Credential Manager (Target: $Target)" -Level "DEBUG"
        }
        return $true
    }

    Write-Host ""
    Write-Host $PromptTitle -ForegroundColor Yellow
    if ($PromptDetails) {
        Write-Host $PromptDetails -ForegroundColor Gray
    }

    $newCredential = Get-Credential -Message $PromptTitle -UserName $DefaultUsername
    if (-not $newCredential) {
        return $false
    }

    return (Save-WindowsCredential -Target $Target -Credential $newCredential)
}

function ConvertFrom-SecureStringPlainText {
    param([Security.SecureString]$SecureString)

    if (-not $SecureString) {
        return ""
    }

    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Initialize-SlackWebhook {
    param(
        [string]$Target,
        [string]$Mode
    )

    if ($Mode -eq "none") {
        return $null
    }

    $credential = Get-WindowsCredential -Target $Target
    if ($credential -and -not [string]::IsNullOrWhiteSpace($credential.Password)) {
        return $credential.Password
    }

    $isInteractive = [Environment]::UserInteractive -and ($Host.Name -like "*ConsoleHost*")
    if (-not $isInteractive) {
        return $null
    }

    Write-Host ""
    Write-Host "Slack увімкнено, але webhook не знайдено в Windows Credential Manager." -ForegroundColor Yellow
    Write-Host "Запис Credential Manager: $Target" -ForegroundColor Gray
    $answer = Read-Host "Ввести Slack webhook і зберегти його в системі? [Y/N]"

    if ($answer -notmatch '^(Y|y|Так|так|Т|т)$') {
        return $null
    }

    $secureWebhook = Read-Host "Введіть Slack webhook URL" -AsSecureString
    $webhook = ConvertFrom-SecureStringPlainText -SecureString $secureWebhook
    if ([string]::IsNullOrWhiteSpace($webhook)) {
        Write-Host "Slack webhook порожній. Slack вимкнено для цього запуску." -ForegroundColor Yellow
        return $null
    }

    if ($webhook -notmatch '^https://') {
        Write-Host "Slack webhook має починатися з https://. Slack вимкнено для цього запуску." -ForegroundColor Yellow
        return $null
    }

    if (Save-SecretToCredentialManager -Target $Target -Username "webhook" -Secret $webhook) {
        Write-Host "Slack webhook збережено в Windows Credential Manager." -ForegroundColor Green
        return $webhook
    }

    Write-Host "Не вдалося зберегти Slack webhook у Windows Credential Manager. Slack вимкнено для цього запуску." -ForegroundColor Yellow
    return $null
}
