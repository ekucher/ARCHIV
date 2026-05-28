$global:BravoConfig = @{
    # Object identity
    ObjectName = "Object name"

    # Services and processes
    BravoServiceName = "BRAVO"
    ExchangAPIServiceName = "exchangAPI"
    ExchangAPIProcessName = "exchangAPI"

    # Archive and restore
    ArchivePrefix = "example_prefix"
    RestoreDay = 7
    RestoreTime = "23:00"
    ArchiveRetentionDays = 14
    RestoreArchivesKeepCount = 1
    LogRetentionDays = 180

    MinFreeSpaceGB = 10
    MaxMdFileSizeGB = 1.5
    ExcludedMdSizeCheckFiles = @(
        "ExampleLargeFile.md"
    )

    # Paths
    BravoWebDir = "D:\Br-a-vo.web"

    # Runtime modes
    AutoShutdown = "off"
    ShutdownTimeout = 60
    ArchivLims = "off"
    # Progress / power-loss recovery
    ProgressStateEnabled = "on"
    ProgressStateMaxAgeHours = 72
    ProgressStateAutoResumeForScheduler = "on"
    # Health checks
    HealthCheckEnabled = "on"
    HealthCheckOnlyFailExitCode = "on"
    HealthCheckArchiveMaxAgeHours = 2
    HealthCheckMinFreeSpaceGB = 10
    HealthCheckDrives = @("C:")
    HealthCheckArchiveCategories = @(
    @{
        Name = "LIMS"
        Path = "{ROOT_LIMS}\ARCHIV\LIMS"
        Pattern = "{ArchivePrefix}_*.mdz"
        Exclude = @(
            "{ArchivePrefix}_before_*.mdz",
            "{ArchivePrefix}_after_*.mdz"
        )
    },
    @{
        Name = "BLOG"
        Path = "{ROOT_LIMS}\ARCHIV\BLOG"
        Pattern = "{ArchivePrefix}_blog_*.mdz"
    },
    @{
        Name = "BRAVOEXCH"
        Path = "{ROOT_LIMS}\ARCHIV\BRAVOEXCH"
        Pattern = "{ArchivePrefix}_bravoexch_*.mdz"
    }
    )

    # Slack
    # Allowed values: "none", "errors_only", "all"
    SlackMode = "all"
    SlackWebhookUrl = ""
    SlackWebhookCredentialTarget = "BRAVO/SlackWebhookUrl"

    # Logging
    # Allowed values: "DEBUG", "INFO", "WARNING", "ERROR", "SUCCESS"
    LogLevel = "INFO"

    SevenZipArchiveArgs = @(
        'a',
        '-mmt',
        '-mx6',
        '-r',
        '-y',
        '-ssw',
        '-bb0',
        '-scrcSHA256',
        '-aoa'
    )

    SevenZipExtractArgs = @(
        'x',
        '-y'
    )

    ArchivePasswordEnabled = "on"
    ArchivePasswordEncryptHeaders = "on"
    ArchiveTempDir = "{ROOT_LIMS}\ARCHIV\TEMP"
    ArchivePassword = ""
    ArchivePasswordCredentialTarget = "BRAVO/ArchivePassword"
    # Console output style:
    # classic = old output, modern = new DevOps-style output
    ConsoleStyle = "classic"
    ConsoleWidth = 80
    ConsoleIcons = "emoji"     # emoji | ascii | off
    ConsoleLabelWidth = 12
    ConsoleStatusWidth = 12


}

