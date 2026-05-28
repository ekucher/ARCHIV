# ==================================================================================================
# BRAVO Progress State / Power-loss Recovery
# ==================================================================================================

# >>> BRAVO_PROGRESS_STATE BEGIN
# --------------------------------
# Progress state / power-loss recovery
# --------------------------------

function ConvertTo-BravoNormalizedSwitch {
    param(
        [object]$Value,
        [string]$Default = "on"
    )

    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) {
        return $Default.ToLowerInvariant()
    }

    return ([string]$Value).ToLowerInvariant()
}

function Read-BravoProgressState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    if (-not (Test-Path -LiteralPath $StatePath)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $StatePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Write-Warning "Could not read progress state '$StatePath': $($_.Exception.Message)"
        return $null
    }
}

function Save-BravoProgressState {
    param(
        [Parameter(Mandatory = $true)]
        [object]$State
    )

    if (-not $script:BravoProgressStateEnabled) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($script:BravoProgressStatePath)) {
        return
    }

    $stateDir = Split-Path -Parent $script:BravoProgressStatePath
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }

    $State.UpdatedAt = (Get-Date).ToString("o")

    $json = $State | ConvertTo-Json -Depth 12
    $tmpPath = "$script:BravoProgressStatePath.tmp"

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($tmpPath, $json, $utf8Bom)

    Move-Item -LiteralPath $tmpPath -Destination $script:BravoProgressStatePath -Force
}

function New-BravoProgressState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [hashtable]$Metadata = @{}
    )

    return [PSCustomObject]@{
        SchemaVersion  = 1
        RunId          = $RunId
        Status         = "Running"
        StartedAt      = (Get-Date).ToString("o")
        UpdatedAt      = (Get-Date).ToString("o")
        FinishedAt     = $null
        ResumeCount    = 0
        CurrentStep    = $null
        CompletedSteps = @()
        Metadata       = $Metadata
        Host           = $env:COMPUTERNAME
        User           = "$env:USERDOMAIN\$env:USERNAME"
        ProcessId      = $PID
    }
}

function Get-BravoCompletedStepIds {
    if (-not $script:BravoProgressState -or -not $script:BravoProgressState.CompletedSteps) {
        return @()
    }

    return @($script:BravoProgressState.CompletedSteps) |
        Where-Object { $_ -and $_.Id } |
        ForEach-Object { [string]$_.Id }
}

function Test-BravoProgressStepCompleted {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepId
    )

    return ((Get-BravoCompletedStepIds) -contains $StepId)
}

function Set-BravoProgressStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepId,

        [Parameter(Mandatory = $true)]
        [string]$StepName
    )

    if (-not $script:BravoProgressStateEnabled -or -not $script:BravoProgressState) {
        return
    }

    $script:BravoProgressState.Status = "Running"
    $script:BravoProgressState.CurrentStep = [PSCustomObject]@{
        Id        = $StepId
        Name      = $StepName
        StartedAt = (Get-Date).ToString("o")
    }

    Save-BravoProgressState -State $script:BravoProgressState

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message "Checkpoint START: $StepId - $StepName" -Level "DEBUG"
    }
}

function Complete-BravoProgressStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StepId,

        [string]$StepName = "",

        [hashtable]$Metadata = @{}
    )

    if (-not $script:BravoProgressStateEnabled -or -not $script:BravoProgressState) {
        return
    }

    if (-not (Test-BravoProgressStepCompleted -StepId $StepId)) {
        $completed = @($script:BravoProgressState.CompletedSteps)
        $completed += [PSCustomObject]@{
            Id          = $StepId
            Name        = $StepName
            CompletedAt = (Get-Date).ToString("o")
            Metadata    = $Metadata
        }

        $script:BravoProgressState.CompletedSteps = $completed
    }

    if ($script:BravoProgressState.CurrentStep -and $script:BravoProgressState.CurrentStep.Id -eq $StepId) {
        $script:BravoProgressState.CurrentStep = $null
    }

    Save-BravoProgressState -State $script:BravoProgressState

    if (Get-Command Write-Log -ErrorAction SilentlyContinue) {
        Write-Log -Message "Checkpoint DONE: $StepId" -Level "DEBUG"
    }
}

function Close-BravoProgressState {
    param(
        [ValidateSet("Completed", "CompletedWithErrors", "Interrupted")]
        [string]$Status = "Completed"
    )

    if (-not $script:BravoProgressStateEnabled -or -not $script:BravoProgressState) {
        return
    }

    $script:BravoProgressState.Status = $Status
    $script:BravoProgressState.CurrentStep = $null

    $finishedAt = (Get-Date).ToString("o")
    if ($script:BravoProgressState.PSObject.Properties["FinishedAt"]) {
        $script:BravoProgressState.FinishedAt = $finishedAt
    }
    else {
        # FinishedAt property is missing in older/existing state files.
        $script:BravoProgressState | Add-Member -NotePropertyName "FinishedAt" -NotePropertyValue $finishedAt -Force
    }

    Save-BravoProgressState -State $script:BravoProgressState
}

function Show-BravoProgressState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    $state = Read-BravoProgressState -StatePath $StatePath

    if (-not $state) {
        Write-Host "Progress state not found: $StatePath" -ForegroundColor Yellow
        return
    }

    Write-Host "Progress state: $StatePath" -ForegroundColor Cyan
    Write-Host "RunId:   $($state.RunId)"
    Write-Host "Status:  $($state.Status)"
    Write-Host "Started: $($state.StartedAt)"
    Write-Host "Updated: $($state.UpdatedAt)"
    Write-Host "User:    $($state.User)"
    Write-Host "Host:    $($state.Host)"

    if ($state.CurrentStep) {
        Write-Host "Current step: $($state.CurrentStep.Id) - $($state.CurrentStep.Name)" -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Completed steps:" -ForegroundColor Cyan

    foreach ($step in @($state.CompletedSteps)) {
        if ($step) {
            Write-Host (" - {0} [{1}]" -f $step.Id, $step.CompletedAt)
        }
    }

    if ($state.Metadata) {
        Write-Host ""
        Write-Host "Metadata:" -ForegroundColor Cyan
        $state.Metadata | Format-List
    }
}

function Initialize-BravoProgressState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [hashtable]$Metadata = @{},

        [string]$Enabled = "on",

        [int]$MaxAgeHours = 72,

        [string]$AutoResumeForScheduler = "on",

        [string]$TaskUserName = "BRAVO_Scheduler",

        [switch]$Reset,

        [switch]$Ignore
    )

    $script:BravoProgressStateEnabled = ((ConvertTo-BravoNormalizedSwitch -Value $Enabled -Default "on") -eq "on")
    $script:BravoProgressStatePath = $StatePath
    $script:BravoProgressStateWasResumed = $false

    if (-not $script:BravoProgressStateEnabled) {
        $script:BravoProgressState = $null
        return
    }

    $stateDir = Split-Path -Parent $StatePath
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -Path $stateDir -ItemType Directory -Force | Out-Null
    }

    if ($Reset -and (Test-Path -LiteralPath $StatePath)) {
        $archiveDir = Join-Path $stateDir "reset"
        New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null

        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        Move-Item -LiteralPath $StatePath -Destination (Join-Path $archiveDir "BRAVO_MAINTENANCE_STATE_$stamp.json") -Force
        Write-Host "Previous progress state moved to reset archive." -ForegroundColor Yellow
    }

    $existingState = $null
    if (-not $Ignore) {
        $existingState = Read-BravoProgressState -StatePath $StatePath
    }

    if ($existingState -and $existingState.Status -in @("Running", "Interrupted")) {
        $stateAgeHours = 0
        try {
            $stateAgeHours = ((Get-Date) - [DateTime]::Parse($existingState.UpdatedAt)).TotalHours
        }
        catch {
            $stateAgeHours = 0
        }

        $isFreshEnough = ($MaxAgeHours -le 0 -or $stateAgeHours -le $MaxAgeHours)
        $isSchedulerUser = ($env:USERNAME -ieq $TaskUserName)
        $autoResume = ((ConvertTo-BravoNormalizedSwitch -Value $AutoResumeForScheduler -Default "on") -eq "on")

        $isRestoreStepInProgress = $false
        if ($existingState.CurrentStep -and [string]$existingState.CurrentStep.Id -eq "RESTORE_MODEL") {
            $isRestoreStepInProgress = $true
        }

        if ($isRestoreStepInProgress) {
            $message = "Виявлено незавершену реставрацію моделі: RunId=$($existingState.RunId), UpdatedAt=$($existingState.UpdatedAt). Автоматичне продовження заблоковано. Перевірте MODEL вручну. Якщо стан моделі коректний, запустіть скрипт із -ResetProgress."
            Write-Host $message -ForegroundColor Red

            if (Get-Command Send-SlackAlert -ErrorAction SilentlyContinue) {
                Send-SlackAlert -Message $message -IsCritical
            }

            throw $message
        }

        if ($isFreshEnough) {
            $resume = $false

            if ($isSchedulerUser -and $autoResume) {
                $resume = $true
                Write-Host "Unfinished progress state found. Scheduler user will resume automatically." -ForegroundColor Yellow
            }
            elseif ([Environment]::UserInteractive -and -not [Console]::IsInputRedirected) {
                Write-Host "Unfinished progress state found:" -ForegroundColor Yellow
                Write-Host "  RunId: $($existingState.RunId)"
                Write-Host "  Status: $($existingState.Status)"
                Write-Host "  CurrentStep: $($existingState.CurrentStep.Id) - $($existingState.CurrentStep.Name)"
                Write-Host "  UpdatedAt: $($existingState.UpdatedAt)"
                $answer = Read-Host "Continue with this progress state? Type YES to continue, RESET to archive it and start fresh"

                if ($answer -eq "YES") {
                    $resume = $true
                }
                elseif ($answer -eq "RESET") {
                    $archiveDir = Join-Path $stateDir "reset"
                    New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
                    $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
                    Move-Item -LiteralPath $StatePath -Destination (Join-Path $archiveDir "BRAVO_MAINTENANCE_STATE_$stamp.json") -Force
                    $existingState = $null
                }
                else {
                    throw "Progress state exists and was not resumed. Use -ResetProgress or -IgnoreProgress if needed."
                }
            }
            else {
                throw "Unfinished progress state exists and this run is non-interactive. Use -ResetProgress, -IgnoreProgress, or enable ProgressStateAutoResumeForScheduler."
            }

            if ($resume) {
                $script:BravoProgressState = $existingState
                $script:BravoProgressState.Status = "Running"
                $script:BravoProgressState.ResumeCount = [int]($script:BravoProgressState.ResumeCount) + 1
                $script:BravoProgressState.ProcessId = $PID
                $script:BravoProgressStateWasResumed = $true
                Save-BravoProgressState -State $script:BravoProgressState
                return
            }
        }
        else {
            $archiveDir = Join-Path $stateDir "stale"
            New-Item -Path $archiveDir -ItemType Directory -Force | Out-Null
            $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
            Move-Item -LiteralPath $StatePath -Destination (Join-Path $archiveDir "BRAVO_MAINTENANCE_STATE_$stamp.json") -Force
            Write-Host "Stale progress state moved to archive." -ForegroundColor Yellow
        }
    }

    $script:BravoProgressState = New-BravoProgressState -RunId $RunId -Metadata $Metadata
    Save-BravoProgressState -State $script:BravoProgressState
}
# <<< BRAVO_PROGRESS_STATE END