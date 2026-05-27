$global:BravoConfig = @{
    ObjectName = "Назва установи"
    BravoServiceName = "BRAVO"
    ExchangAPIServiceName = "exchangAPI"
    ExchangAPIProcessName = "exchangAPI"
    ArchivePrefix = "example_prefix"
    RestoreDay = 7
    RestoreTime = "23:00"
    ArchiveRetentionDays = 14
    RestoreArchivesKeepCount = 1
    LogRetentionDays = 180
    MinFreeSpaceGB = 10
    MaxMdFileSizeGB = 1.5
    BravoWebDir = "D:\Br-a-vo.web"
    SlackMode = "errors_only"
    SlackWebhookUrl = ""
    ArchivePassword = ""
}