# ==================================================================================================
# BRAVO Script Parameters
# ==================================================================================================

param (
    [switch]$ForceRestore,
    [switch]$DisableSizeCheck,
    [switch]$EnableAllSlack,
    [switch]$DisableAllSlack,

    [ValidateSet("on", "off")]
    [string]$AutoShutdown,

    [ValidateSet("on", "off")]
    [string]$ArchivLims,

    [switch]$SetupCredentials,
    [switch]$InstallScheduledTask,

    [string]$TaskName = "BRAVO Maintenance",
    [string]$TaskUserName = "BRAVO_Scheduler",
    [string]$TaskTime = "23:00",

    [ValidateSet("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")]
    [string[]]$TaskDaysOfWeek = @("Sunday"),

    [switch]$AddTaskUserToAdministrators,
    [switch]$ResetTaskUserPassword,
    [switch]$SkipTaskUserCredentialBootstrap,

    [switch]$ResetProgress,
    [switch]$IgnoreProgress,
    [switch]$ShowProgressState,

    [switch]$HealthCheckOnly,
    [switch]$SkipHealthCheck
)