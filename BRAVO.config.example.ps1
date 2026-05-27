$global:BravoConfig = @{
    # Object identity
    ObjectName = "Object name"

    # Services and processes
    BravoServiceName = "BRAVO"
    ExchangAPIServiceName = "exchangAPI"
    ExchangAPIProcessName = "exchangAPI"

    # Archive and restore
    ArchivePrefix = "example_prefix"
    ArchivePassword = ""

    RestoreDay = 7
    RestoreTime = "23:00"
    ArchiveRetentionDays = 14
    RestoreArchivesKeepCount = 1
    LogRetentionDays = 180

    MinFreeSpaceGB = 10
    MaxMdFileSizeGB = 1.5

    # Paths
    BravoWebDir = "D:\Br-a-vo.web"

    # Runtime modes
    AutoShutdown = "off"
    ShutdownTimeout = 60
    ArchivLims = "off"

    # Slack
    # Allowed values: "none", "errors_only", "all"
    SlackMode = "errors_only"
    SlackWebhookUrl = ""

    # Logging
    # Allowed values: "DEBUG", "INFO", "WARNING", "ERROR", "SUCCESS"
    LogLevel = "INFO"
}
