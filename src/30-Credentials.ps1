# ==================================================================================================
# BRAVO Credentials / Windows Credential Manager / Scheduled Task User
# ==================================================================================================

# >>> BRAVO_SCHEDULER_CREDENTIALS_ADDON BEGIN
# ==============================================================================
# BRAVO monolith add-on: Windows Credential Manager + Scheduled Task user
# Insert this block into BRAVO_MAINTENANCE.ps1 after Get-BravoConfigValue
# and before reading ArchivePassword / SlackWebhookUrl from config.
# ==============================================================================

# ------------------------------
# Windows Credential Manager API
# ------------------------------

function Initialize-BravoCredentialApi {
    if ("BravoCredentialNative" -as [type]) {
        return
    }

    $source = @"
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

public static class BravoCredentialNative
{
    public const UInt32 CRED_TYPE_GENERIC = 1;
    public const UInt32 CRED_PERSIST_LOCAL_MACHINE = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL
    {
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

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredRead(string target, UInt32 type, UInt32 reservedFlag, out IntPtr credentialPtr);

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredWrite(ref CREDENTIAL credential, UInt32 flags);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredDelete(string target, UInt32 type, UInt32 flags);

    [DllImport("advapi32.dll", SetLastError = false)]
    public static extern void CredFree(IntPtr buffer);
}
"@

    Add-Type -TypeDefinition $source -ErrorAction Stop
}

function ConvertFrom-BravoSecureStringPlainText {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Save-BravoWindowsCredential {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$Secret
    )

    Initialize-BravoCredentialApi

    if ([string]::IsNullOrWhiteSpace($Target)) {
        throw "Credential target is empty"
    }

    if ([string]::IsNullOrWhiteSpace($UserName)) {
        $UserName = "BRAVO"
    }

    $secretBytes = [System.Text.Encoding]::Unicode.GetBytes($Secret)
    if ($secretBytes.Length -gt 5120) {
        throw "Credential secret is too large for Windows Credential Manager target '$Target'"
    }

    $blobPtr = [Runtime.InteropServices.Marshal]::AllocCoTaskMem($secretBytes.Length)

    try {
        [Runtime.InteropServices.Marshal]::Copy($secretBytes, 0, $blobPtr, $secretBytes.Length)

        $credential = New-Object BravoCredentialNative+CREDENTIAL
        $credential.Flags = 0
        $credential.Type = [BravoCredentialNative]::CRED_TYPE_GENERIC
        $credential.TargetName = $Target
        $credential.UserName = $UserName
        $credential.CredentialBlobSize = [uint32]$secretBytes.Length
        $credential.CredentialBlob = $blobPtr
        $credential.Persist = [BravoCredentialNative]::CRED_PERSIST_LOCAL_MACHINE
        $credential.AttributeCount = 0
        $credential.Attributes = [IntPtr]::Zero
        $credential.TargetAlias = $null
        $credential.Comment = "BRAVO automation credential"

        $ok = [BravoCredentialNative]::CredWrite([ref]$credential, 0)
        if (-not $ok) {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "CredWrite failed for target '$Target'. Win32 error: $err"
        }
    }
    finally {
        if ($blobPtr -ne [IntPtr]::Zero) {
            if ($secretBytes) {
                $zeroBytes = New-Object byte[] $secretBytes.Length
                [Runtime.InteropServices.Marshal]::Copy($zeroBytes, 0, $blobPtr, $zeroBytes.Length)
            }
            [Runtime.InteropServices.Marshal]::FreeCoTaskMem($blobPtr)
        }

        if ($secretBytes) {
            [Array]::Clear($secretBytes, 0, $secretBytes.Length)
        }
    }
}

function Get-BravoWindowsCredential {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    Initialize-BravoCredentialApi

    $credentialPtr = [IntPtr]::Zero
    $ok = [BravoCredentialNative]::CredRead(
        $Target,
        [BravoCredentialNative]::CRED_TYPE_GENERIC,
        0,
        [ref]$credentialPtr
    )

    if (-not $ok) {
        return $null
    }

    try {
        $credential = [Runtime.InteropServices.Marshal]::PtrToStructure(
            $credentialPtr,
            [type][BravoCredentialNative+CREDENTIAL]
        )

        $secret = ""
        if ($credential.CredentialBlob -ne [IntPtr]::Zero -and $credential.CredentialBlobSize -gt 0) {
            $charCount = [int]($credential.CredentialBlobSize / 2)
            $secret = [Runtime.InteropServices.Marshal]::PtrToStringUni($credential.CredentialBlob, $charCount)
        }

        [PSCustomObject]@{
            TargetName = $credential.TargetName
            UserName   = $credential.UserName
            Secret     = $secret
        }
    }
    finally {
        if ($credentialPtr -ne [IntPtr]::Zero) {
            [BravoCredentialNative]::CredFree($credentialPtr)
        }
    }
}

function Remove-BravoWindowsCredential {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target
    )

    Initialize-BravoCredentialApi

    $ok = [BravoCredentialNative]::CredDelete(
        $Target,
        [BravoCredentialNative]::CRED_TYPE_GENERIC,
        0
    )

    if (-not $ok) {
        $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()

        # 1168 = ERROR_NOT_FOUND
        if ($err -ne 1168) {
            throw "CredDelete failed for target '$Target'. Win32 error: $err"
        }
    }
}

function Save-BravoSecretInteractive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [string]$UserName = "BRAVO",

        [string]$Prompt = "Enter secret"
    )

    $secureSecret = Read-Host -Prompt $Prompt -AsSecureString
    $plainSecret = ConvertFrom-BravoSecureStringPlainText -SecureString $secureSecret

    try {
        Save-BravoWindowsCredential -Target $Target -UserName $UserName -Secret $plainSecret
    }
    finally {
        $plainSecret = $null
    }
}

function Get-BravoSecret {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Target,

        [string]$ConfigValue = "",

        [switch]$Required
    )

    $credential = Get-BravoWindowsCredential -Target $Target
    if ($credential -and -not [string]::IsNullOrWhiteSpace($credential.Secret)) {
        return [string]$credential.Secret
    }

    # Backward compatibility while migrating old configs.
    # After migration, keep sensitive values empty in BRAVO.config.ps1.
    if (-not [string]::IsNullOrWhiteSpace($ConfigValue)) {
        Write-Warning "$Name is still read from BRAVO.config.ps1. Move it to Windows Credential Manager target '$Target'."
        return [string]$ConfigValue
    }

    if ($Required) {
        throw "Required secret is missing: $Name. Save it to Windows Credential Manager target '$Target'."
    }

    return ""
}

function Invoke-BravoCredentialSetup {
    param(
        [string]$ArchivePasswordTarget = "BRAVO/ArchivePassword",
        [string]$SlackWebhookTarget = "BRAVO/SlackWebhookUrl",
        [string]$SlackMode = "errors_only",
        [string]$ArchivePasswordEnabled = "on"
    )

    Write-Host "Saving BRAVO secrets to Windows Credential Manager for current Windows user: $env:USERDOMAIN\$env:USERNAME" -ForegroundColor Cyan
    Write-Host "Important: Windows Credential Manager credentials are per Windows user." -ForegroundColor Yellow
    Write-Host "If the scheduled task runs as another user, save these secrets under that same user account." -ForegroundColor Yellow

    $normalizedArchivePasswordEnabled = if ([string]::IsNullOrWhiteSpace($ArchivePasswordEnabled)) {
        "on"
    }
    else {
        $ArchivePasswordEnabled.ToLowerInvariant()
    }

    if ($normalizedArchivePasswordEnabled -notin @("on", "off")) {
        throw "ArchivePasswordEnabled must be 'on' or 'off'. Current value: $ArchivePasswordEnabled"
    }

    if ($normalizedArchivePasswordEnabled -eq "on") {
        Write-Host "ArchivePasswordEnabled is 'on'. Archive password should be saved for encrypted archives." -ForegroundColor Cyan
        Save-BravoSecretInteractive `
            -Target $ArchivePasswordTarget `
            -UserName "BRAVO" `
            -Prompt "Archive password"
    }
    else {
        Write-Host "ArchivePasswordEnabled is 'off'. Archive password prompt skipped." -ForegroundColor Yellow
    }

    $normalizedSlackMode = if ([string]::IsNullOrWhiteSpace($SlackMode)) {
        "none"
    }
    else {
        $SlackMode.ToLowerInvariant()
    }

    $slackEnabled = ($normalizedSlackMode -notin @("none", "off"))

    if ($slackEnabled) {
        Write-Host "SlackMode is '$SlackMode'. Slack webhook URL should be saved for notifications." -ForegroundColor Cyan
        $saveSlack = Read-Host "Save or replace Slack webhook URL now? Type YES to save"

        if ($saveSlack -eq "YES") {
            Save-BravoSecretInteractive `
                -Target $SlackWebhookTarget `
                -UserName "BRAVO" `
                -Prompt "Slack webhook URL"
        }
        else {
            Write-Warning "SlackMode is '$SlackMode', but Slack webhook URL was not saved. Slack will be disabled at runtime if the URL is missing."
        }
    }
    else {
        Write-Host "SlackMode is '$SlackMode'. Slack webhook URL prompt skipped." -ForegroundColor Yellow
    }

    Write-Host "Credentials saved." -ForegroundColor Green
}

# --------------------------------
# Scheduled task dedicated user API
# --------------------------------

function Test-BravoAdministrator {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )

    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-BravoRandomPassword {
    param(
        [int]$Length = 32
    )

    if ($Length -lt 16) {
        throw "Password length must be at least 16"
    }

    $upper = "ABCDEFGHJKLMNPQRSTUVWXYZ"
    $lower = "abcdefghijkmnopqrstuvwxyz"
    $digit = "23456789"
    $special = "!#@_-+="
    $all = ($upper + $lower + $digit + $special).ToCharArray()

    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()

    function Get-RandomCharFromSet {
        param([string]$Set)

        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
        $index = [BitConverter]::ToUInt32($bytes, 0) % $Set.Length
        return $Set[[int]$index]
    }

    $chars = New-Object System.Collections.Generic.List[char]
    [void]$chars.Add((Get-RandomCharFromSet $upper))
    [void]$chars.Add((Get-RandomCharFromSet $lower))
    [void]$chars.Add((Get-RandomCharFromSet $digit))
    [void]$chars.Add((Get-RandomCharFromSet $special))

    while ($chars.Count -lt $Length) {
        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
        $index = [BitConverter]::ToUInt32($bytes, 0) % $all.Length
        [void]$chars.Add($all[[int]$index])
    }

    # Shuffle
    for ($i = 0; $i -lt $chars.Count; $i++) {
        $bytes = New-Object byte[] 4
        $rng.GetBytes($bytes)
        $j = [int]([BitConverter]::ToUInt32($bytes, 0) % $chars.Count)

        $tmp = $chars[$i]
        $chars[$i] = $chars[$j]
        $chars[$j] = $tmp
    }

    $rng.Dispose()
    return -join $chars
}

function Get-BravoLocalUserSid {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    $account = New-Object System.Security.Principal.NTAccount($env:COMPUTERNAME, $UserName)
    return $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

function Set-BravoUserRight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Sid,

        [Parameter(Mandatory = $true)]
        [string]$Privilege
    )

    $tempDir = Join-Path $env:TEMP ("bravo_secedit_" + [guid]::NewGuid().ToString("N"))
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

    $cfgPath = Join-Path $tempDir "secpol.inf"
    $dbPath = Join-Path $tempDir "secpol.sdb"

    try {
        & secedit.exe /export /cfg $cfgPath | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $cfgPath)) {
            throw "secedit export failed"
        }

        $content = @(Get-Content -Path $cfgPath -Encoding Unicode)
        $entry = "*$Sid"

        $lineIndex = -1
        for ($i = 0; $i -lt $content.Count; $i++) {
            if ($content[$i] -match "^\s*$([regex]::Escape($Privilege))\s*=") {
                $lineIndex = $i
                break
            }
        }

        $currentValues = @()
        if ($lineIndex -ge 0) {
            $rightPart = ($content[$lineIndex] -split "=", 2)[1]
            $currentValues = @(
                $rightPart -split "," |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            )
        }

        if ($currentValues -notcontains $entry) {
            $currentValues += $entry
        }

        $newLine = "$Privilege = $($currentValues -join ',')"

        if ($lineIndex -ge 0) {
            $content[$lineIndex] = $newLine
        }
        else {
            $privilegeSectionIndex = -1
            for ($i = 0; $i -lt $content.Count; $i++) {
                if ($content[$i] -eq "[Privilege Rights]") {
                    $privilegeSectionIndex = $i
                    break
                }
            }

            $list = New-Object System.Collections.Generic.List[string]
            $content | ForEach-Object { [void]$list.Add($_) }

            if ($privilegeSectionIndex -ge 0) {
                $list.Insert($privilegeSectionIndex + 1, $newLine)
            }
            else {
                [void]$list.Add("[Privilege Rights]")
                [void]$list.Add($newLine)
            }

            $content = $list.ToArray()
        }

        Set-Content -Path $cfgPath -Value $content -Encoding Unicode

        & secedit.exe /configure /db $dbPath /cfg $cfgPath /areas USER_RIGHTS | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "secedit configure failed for privilege '$Privilege'"
        }
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Hide-BravoLocalUserFromLogonScreen {
    param(
        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    $key = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\SpecialAccounts\UserList"
    New-Item -Path $key -Force | Out-Null

    New-ItemProperty `
        -Path $key `
        -Name $UserName `
        -PropertyType DWord `
        -Value 0 `
        -Force | Out-Null
}

function Get-BravoBuiltinAdministratorsGroupName {
    $sid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $account = $sid.Translate([System.Security.Principal.NTAccount]).Value
    return ($account -split "\\")[-1]
}

function Add-BravoLocalGroupMemberCompatible {
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(Mandatory = $true)]
        [string]$UserName
    )

    if ($GroupName -eq "Administrators") {
        $GroupName = Get-BravoBuiltinAdministratorsGroupName
    }

    if (Get-Command Add-LocalGroupMember -ErrorAction SilentlyContinue) {
        $member = "$env:COMPUTERNAME\$UserName"
        Add-LocalGroupMember -Group $GroupName -Member $member -ErrorAction SilentlyContinue
    }
    else {
        & net.exe localgroup $GroupName $UserName /add | Out-Null
    }
}

function Ensure-BravoSchedulerUser {
    param(
        [string]$UserName = "BRAVO_Scheduler",

        [string]$Password = "",

        [switch]$ResetPassword,

        [switch]$AddToAdministrators
    )

    if (-not (Test-BravoAdministrator)) {
        throw "Administrator rights are required to create and configure the scheduler user."
    }

    if ($UserName -match '[\\/@]') {
        throw "UserName must be a local account name only, without domain or computer prefix."
    }

    if ([string]::IsNullOrWhiteSpace($Password)) {
        $Password = New-BravoRandomPassword
    }

    $securePassword = ConvertTo-SecureString $Password -AsPlainText -Force

    $localUserExists = $false
    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        $localUserExists = [bool](Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)

        if (-not $localUserExists) {
            New-LocalUser `
                -Name $UserName `
                -Password $securePassword `
                -Description "BRAVO scheduler account" `
                -PasswordNeverExpires `
                -UserMayNotChangePassword `
                -ErrorAction Stop | Out-Null
        }
        elseif ($ResetPassword) {
            Set-LocalUser -Name $UserName -Password $securePassword -PasswordNeverExpires $true -ErrorAction Stop
        }
    }
    else {
        & net.exe user $UserName $Password /add /expires:never /passwordchg:no | Out-Null
        if ($LASTEXITCODE -ne 0 -and -not $ResetPassword) {
            # User may already exist. Continue and try to configure it.
        }

        if ($ResetPassword) {
            & net.exe user $UserName $Password | Out-Null
        }

        & wmic.exe useraccount where "name='$UserName'" set PasswordExpires=FALSE | Out-Null
    }

    if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
        if (-not (Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue)) {
            throw "Scheduler user '$UserName' was not created."
        }
    }

    if ($AddToAdministrators) {
        Add-BravoLocalGroupMemberCompatible -GroupName "Administrators" -UserName $UserName
    }

    $sid = Get-BravoLocalUserSid -UserName $UserName

    # Required for Task Scheduler with stored password.
    Set-BravoUserRight -Sid $sid -Privilege "SeBatchLogonRight"

    # Make account non-interactive.
    Set-BravoUserRight -Sid $sid -Privilege "SeDenyInteractiveLogonRight"
    Set-BravoUserRight -Sid $sid -Privilege "SeDenyRemoteInteractiveLogonRight"

    # Hide from Windows welcome/logon screen. This is not a security boundary.
    Hide-BravoLocalUserFromLogonScreen -UserName $UserName

    [PSCustomObject]@{
        UserName = $UserName
        FullName = "$env:COMPUTERNAME\$UserName"
        Sid = $sid
        Password = $Password
    }
}

function Invoke-BravoTaskUserCredentialBootstrap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskUserName,

        [Parameter(Mandatory = $true)]
        [string]$TaskUserPassword,

        [Parameter(Mandatory = $true)]
        [string]$ArchivePasswordTarget,

        [string]$ArchivePasswordEnabled = "on",

        [string]$ArchivePasswordSecret = "",

        [Parameter(Mandatory = $true)]
        [string]$SlackWebhookTarget,

        [string]$SlackWebhookSecret = "",

        [int]$TimeoutSeconds = 90
    )

    if (-not (Test-BravoAdministrator)) {
        throw "Administrator rights are required to bootstrap task-user credentials."
    }

    $normalizedArchivePasswordEnabled = if ([string]::IsNullOrWhiteSpace($ArchivePasswordEnabled)) {
        "on"
    }
    else {
        $ArchivePasswordEnabled.ToLowerInvariant()
    }

    if ($normalizedArchivePasswordEnabled -notin @("on", "off")) {
        throw "ArchivePasswordEnabled must be 'on' or 'off'. Current value: $ArchivePasswordEnabled"
    }

    if ($normalizedArchivePasswordEnabled -eq "on" -and [string]::IsNullOrWhiteSpace($ArchivePasswordSecret)) {
        throw "ArchivePasswordSecret is empty while ArchivePasswordEnabled is 'on'. Run -SetupCredentials first or keep ArchivePassword in local config during migration."
    }

    $bootstrapId = [guid]::NewGuid().ToString("N")
    $bootstrapRoot = Join-Path $env:ProgramData "BRAVO\CredentialBootstrap\$bootstrapId"

    New-Item -Path $bootstrapRoot -ItemType Directory -Force | Out-Null

    $payloadPath = Join-Path $bootstrapRoot "payload.json"
    $scriptPath = Join-Path $bootstrapRoot "bootstrap.ps1"
    $resultPath = Join-Path $bootstrapRoot "result.txt"
    $logPath = Join-Path $bootstrapRoot "bootstrap.log"
    $taskName = "BRAVO Credential Bootstrap $bootstrapId"
    $taskPath = "\BRAVO\"

    try {
        $acl = New-Object System.Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)

        $systemSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
        $adminsSid = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
        $taskUserSid = New-Object System.Security.Principal.SecurityIdentifier((Get-BravoLocalUserSid -UserName $TaskUserName))

        foreach ($sid in @($systemSid, $adminsSid, $taskUserSid)) {
            $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
                $sid,
                "FullControl",
                "ContainerInherit,ObjectInherit",
                "None",
                "Allow"
            )
            $acl.AddAccessRule($rule) | Out-Null
        }

        Set-Acl -LiteralPath $bootstrapRoot -AclObject $acl

        $payload = [PSCustomObject]@{
            ArchivePasswordEnabled = $normalizedArchivePasswordEnabled
            ArchivePasswordTarget = $ArchivePasswordTarget
            ArchivePasswordSecret = $ArchivePasswordSecret
            SlackWebhookTarget = $SlackWebhookTarget
            SlackWebhookSecret = $SlackWebhookSecret
        }

        $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $payloadPath -Encoding UTF8

        $bootstrapScript = @'
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadPath,

    [Parameter(Mandatory = $true)]
    [string]$ResultPath,

    [Parameter(Mandatory = $true)]
    [string]$LogPath
)

$ErrorActionPreference = "Stop"

function Write-BootstrapLog {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}

function Initialize-BravoCredentialBootstrapApi {
    if ("BravoCredentialNativeBootstrap" -as [type]) {
        return
    }

    $source = @"
using System;
using System.Runtime.InteropServices;

public static class BravoCredentialNativeBootstrap
{
    public const UInt32 CRED_TYPE_GENERIC = 1;
    public const UInt32 CRED_PERSIST_LOCAL_MACHINE = 2;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct CREDENTIAL
    {
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

    [DllImport("advapi32.dll", EntryPoint = "CredWriteW", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern bool CredWrite(ref CREDENTIAL credential, UInt32 flags);
}
"@

    Add-Type -TypeDefinition $source -ErrorAction Stop
}

function Save-BravoWindowsCredentialBootstrap {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Target,

        [Parameter(Mandatory = $true)]
        [string]$UserName,

        [Parameter(Mandatory = $true)]
        [string]$Secret
    )

    Initialize-BravoCredentialBootstrapApi

    $secretBytes = [System.Text.Encoding]::Unicode.GetBytes($Secret)

    if ($secretBytes.Length -gt 5120) {
        throw "Credential secret is too large for target '$Target'"
    }

    $blobPtr = [Runtime.InteropServices.Marshal]::AllocCoTaskMem($secretBytes.Length)

    try {
        [Runtime.InteropServices.Marshal]::Copy($secretBytes, 0, $blobPtr, $secretBytes.Length)

        $credential = New-Object BravoCredentialNativeBootstrap+CREDENTIAL
        $credential.Flags = 0
        $credential.Type = [BravoCredentialNativeBootstrap]::CRED_TYPE_GENERIC
        $credential.TargetName = $Target
        $credential.UserName = $UserName
        $credential.CredentialBlobSize = [uint32]$secretBytes.Length
        $credential.CredentialBlob = $blobPtr
        $credential.Persist = [BravoCredentialNativeBootstrap]::CRED_PERSIST_LOCAL_MACHINE
        $credential.AttributeCount = 0
        $credential.Attributes = [IntPtr]::Zero
        $credential.TargetAlias = $null
        $credential.Comment = "BRAVO scheduled task credential"

        $ok = [BravoCredentialNativeBootstrap]::CredWrite([ref]$credential, 0)
        if (-not $ok) {
            $err = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw "CredWrite failed for target '$Target'. Win32 error: $err"
        }
    }
    finally {
        if ($blobPtr -ne [IntPtr]::Zero) {
            if ($secretBytes) {
                $zeroBytes = New-Object byte[] $secretBytes.Length
                [Runtime.InteropServices.Marshal]::Copy($zeroBytes, 0, $blobPtr, $zeroBytes.Length)
            }
            [Runtime.InteropServices.Marshal]::FreeCoTaskMem($blobPtr)
        }

        if ($secretBytes) {
            [Array]::Clear($secretBytes, 0, $secretBytes.Length)
        }
    }
}

try {
    Write-BootstrapLog "Credential bootstrap started as $env:USERDOMAIN\$env:USERNAME"

    $payload = Get-Content -LiteralPath $PayloadPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $archivePasswordEnabled = if ([string]::IsNullOrWhiteSpace([string]$payload.ArchivePasswordEnabled)) {
        "on"
    }
    else {
        ([string]$payload.ArchivePasswordEnabled).ToLowerInvariant()
    }

    if ($archivePasswordEnabled -eq "on") {
        Save-BravoWindowsCredentialBootstrap `
            -Target $payload.ArchivePasswordTarget `
            -UserName "BRAVO" `
            -Secret $payload.ArchivePasswordSecret

        Write-BootstrapLog "Archive password credential saved."
    }
    else {
        Write-BootstrapLog "Archive password disabled by config. Skipped."
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$payload.SlackWebhookSecret)) {
        Save-BravoWindowsCredentialBootstrap `
            -Target $payload.SlackWebhookTarget `
            -UserName "BRAVO" `
            -Secret $payload.SlackWebhookSecret

        Write-BootstrapLog "Slack webhook credential saved."
    }
    else {
        Write-BootstrapLog "Slack webhook credential is empty. Skipped."
    }

    Set-Content -LiteralPath $ResultPath -Value "OK" -Encoding ASCII
    Write-BootstrapLog "Credential bootstrap completed successfully."
}
catch {
    $message = $_.Exception.Message
    Set-Content -LiteralPath $ResultPath -Value "ERROR: $message" -Encoding UTF8
    Write-BootstrapLog "ERROR: $message"
    exit 1
}
'@

        Set-Content -LiteralPath $scriptPath -Value $bootstrapScript -Encoding UTF8

        $action = New-ScheduledTaskAction `
            -Execute "powershell.exe" `
            -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -PayloadPath `"$payloadPath`" -ResultPath `"$resultPath`" -LogPath `"$logPath`""

        $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5)

        $settings = New-ScheduledTaskSettingsSet `
            -StartWhenAvailable `
            -MultipleInstances IgnoreNew `
            -ExecutionTimeLimit (New-TimeSpan -Minutes 10)

        $taskUserFullName = "$env:COMPUTERNAME\$TaskUserName"

        Register-ScheduledTask `
            -TaskName $taskName `
            -TaskPath $taskPath `
            -Action $action `
            -Trigger $trigger `
            -Settings $settings `
            -Description "Temporary BRAVO credential bootstrap task" `
            -User $taskUserFullName `
            -Password $TaskUserPassword `
            -Force | Out-Null

        Start-ScheduledTask -TaskName $taskName -TaskPath $taskPath

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            if (Test-Path -LiteralPath $resultPath) {
                break
            }
            Start-Sleep -Seconds 2
        }

        if (-not (Test-Path -LiteralPath $resultPath)) {
            throw "Credential bootstrap task did not finish within $TimeoutSeconds seconds. Bootstrap log: $logPath"
        }

        $result = Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8
        if ($result -notmatch '^OK') {
            $logText = ""
            if (Test-Path -LiteralPath $logPath) {
                $logText = Get-Content -LiteralPath $logPath -Raw -Encoding UTF8
            }
            throw "Credential bootstrap failed. Result: $result`n$logText"
        }

        Write-Host "Task-user credentials saved for $taskUserFullName." -ForegroundColor Green
    }
    finally {
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction SilentlyContinue

        if (Test-Path -LiteralPath $payloadPath) {
            try {
                $payloadLength = (Get-Item -LiteralPath $payloadPath).Length
                if ($payloadLength -gt 0) {
                    $zeroBytes = New-Object byte[] ([int]$payloadLength)
                    [System.IO.File]::WriteAllBytes($payloadPath, $zeroBytes)
                }
            }
            catch {
                # Ignore wipe failure and continue cleanup.
            }
        }

        Remove-Item -LiteralPath $bootstrapRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Install-BravoScheduledTask {
    param(
        [string]$ArchivePasswordEnabled = "on",


        [string]$TaskName = "BRAVO Maintenance",

        [string]$TaskPath = "\BRAVO\",

        [string]$TaskUserName = "BRAVO_Scheduler",

        [string]$ScriptPath = "",

        [ValidatePattern('^\d{2}:\d{2}$')]
        [string]$At = "23:00",

        [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")]
        [string[]]$DaysOfWeek = @("Sunday"),

        [string]$ScriptArguments = "",

        [switch]$AddTaskUserToAdministrators,

        [switch]$ResetTaskUserPassword
    )

    if (-not (Test-BravoAdministrator)) {
        throw "Administrator rights are required to install the scheduled task."
    }

    if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
        $ScriptPath = Join-Path -Path $PSScriptRoot -ChildPath "BRAVO_MAINTENANCE.ps1"
    }

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        throw "ScriptPath not found: $ScriptPath"
    }

    $password = New-BravoRandomPassword

    $taskUser = Ensure-BravoSchedulerUser `
        -UserName $TaskUserName `
        -Password $password `
        -ResetPassword:$ResetTaskUserPassword `
        -AddToAdministrators:$AddTaskUserToAdministrators

    $normalizedArchivePasswordEnabledForTask = if ([string]::IsNullOrWhiteSpace($ArchivePasswordEnabled)) {
        "on"
    }
    else {
        $ArchivePasswordEnabled.ToLowerInvariant()
    }

    if ($normalizedArchivePasswordEnabledForTask -notin @("on", "off")) {
        throw "ArchivePasswordEnabled must be 'on' or 'off'. Current value: $ArchivePasswordEnabled"
    }

    # Bootstrap task-user Windows Credential Manager secrets.
    if (-not $SkipTaskUserCredentialBootstrap) {
        if ($normalizedArchivePasswordEnabledForTask -eq "on" -and [string]::IsNullOrWhiteSpace($ArchivePasswordSecret)) {
            $archiveCredential = Get-BravoWindowsCredential -Target $ArchivePasswordCredentialTarget
            if ($archiveCredential -and -not [string]::IsNullOrWhiteSpace($archiveCredential.Secret)) {
                $ArchivePasswordSecret = [string]$archiveCredential.Secret
            }
        }

        if ($normalizedArchivePasswordEnabledForTask -eq "on" -and [string]::IsNullOrWhiteSpace($ArchivePasswordSecret)) {
            try {
                $ArchivePasswordSecret = [string](Get-BravoConfigValue -Name "ArchivePassword" -Default "")
            }
            catch {
                $ArchivePasswordSecret = ""
            }
        }

        if ([string]::IsNullOrWhiteSpace($SlackWebhookSecret)) {
            $slackCredential = Get-BravoWindowsCredential -Target $SlackWebhookCredentialTarget
            if ($slackCredential -and -not [string]::IsNullOrWhiteSpace($slackCredential.Secret)) {
                $SlackWebhookSecret = [string]$slackCredential.Secret
            }
        }

        if ([string]::IsNullOrWhiteSpace($SlackWebhookSecret)) {
            try {
                $SlackWebhookSecret = [string](Get-BravoConfigValue -Name "SlackWebhookUrl" -Default "")
            }
            catch {
                $SlackWebhookSecret = ""
            }
        }

        Invoke-BravoTaskUserCredentialBootstrap `
            -TaskUserName $TaskUserName `
            -TaskUserPassword $password `
            -ArchivePasswordEnabled $normalizedArchivePasswordEnabledForTask `
            -ArchivePasswordTarget $ArchivePasswordCredentialTarget `
            -ArchivePasswordSecret $ArchivePasswordSecret `
            -SlackWebhookTarget $SlackWebhookCredentialTarget `
            -SlackWebhookSecret $SlackWebhookSecret
    }
    else {
        Write-Host "Task-user Credential Manager bootstrap skipped by parameter." -ForegroundColor Yellow
    }

    $time = [DateTime]::ParseExact($At, "HH:mm", [Globalization.CultureInfo]::InvariantCulture)

    $argumentLine = "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""
    if (-not [string]::IsNullOrWhiteSpace($ScriptArguments)) {
        $argumentLine = "$argumentLine $ScriptArguments"
    }

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument $argumentLine

    $trigger = New-ScheduledTaskTrigger `
        -Weekly `
        -DaysOfWeek $DaysOfWeek `
        -At $time

    $settings = New-ScheduledTaskSettingsSet `
        -StartWhenAvailable `
        -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Hours 8) `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries

    Register-ScheduledTask `
        -TaskName $TaskName `
        -TaskPath $TaskPath `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Description "BRAVO/LIMS maintenance task" `
        -User $taskUser.FullName `
        -Password $password `
        -RunLevel Highest `
        -Force | Out-Null

    $password = $null

    Write-Host "Scheduled task installed: $TaskPath$TaskName" -ForegroundColor Green
    Write-Host "Task user: $($taskUser.FullName)" -ForegroundColor Green
    Write-Host "User is hidden from Windows logon screen and denied interactive/RDP logon." -ForegroundColor Yellow
    Write-Host "Note: hidden-from-logon is not a security boundary; the account remains visible to administrators." -ForegroundColor Yellow
}
# <<< BRAVO_SCHEDULER_CREDENTIALS_ADDON END
