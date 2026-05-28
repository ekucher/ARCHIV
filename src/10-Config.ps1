# ==================================================================================================
# BRAVO Config
# ==================================================================================================

# ===== LOAD LOCAL CONFIG =====
$configPath = Join-Path -Path $PSScriptRoot -ChildPath "BRAVO.config.ps1"

if (-not (Test-Path $configPath)) {
    throw "BRAVO.config.ps1 not found. Create it from BRAVO.config.example.ps1"
}

. $configPath

if (-not $global:BravoConfig) {
    throw "BRAVO.config.ps1 loaded, but global BravoConfig is not defined"
}

function Get-BravoConfigValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [object]$Default = $null,

        [switch]$Required
    )

    $value = $null
    $hasValue = $false

    if ($global:BravoConfig -is [hashtable]) {
        if ($global:BravoConfig.ContainsKey($Name)) {
            $value = $global:BravoConfig[$Name]
            $hasValue = $true
        }
    }
    else {
        $property = $global:BravoConfig.PSObject.Properties[$Name]
        if ($property) {
            $value = $property.Value
            $hasValue = $true
        }
    }

    if ($hasValue -and $null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
        return $value
    }

    if ($Required) {
        throw "Required config value is missing: $Name"
    }

    return $Default
}