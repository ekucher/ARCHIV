# ARCHIV

PowerShell automation for BravoSoft/LIMS maintenance on Windows.

The project is intended to run from the `ARCHIV` directory inside a LIMS installation root. It performs routine maintenance operations such as service stop/start, model backup, optional model restore, log rotation, archive retention cleanup, and Slack notifications.

## Requirements

- Windows 8.1 / Windows Server 2012 R2 or newer.
- PowerShell 5.1 or newer.
- Run the script as Administrator.
- `7za.exe` must be available in `ARCHIV\Tools\7za.exe`.
- `bravocmd.exe` must be available in the LIMS root directory.
- Local configuration must be created from `BRAVO.config.example.ps1`.

## Expected folder layout

```text
C:\LIMS\
├── ARCHIV\
│   ├── BRAVO_MAINTENANCE.ps1
│   ├── BRAVO.config.example.ps1
│   ├── BRAVO.config.ps1          # local file, ignored by Git
│   ├── Tools\
│   │   └── 7za.exe               # local tool, ignored by Git
│   ├── LOGS\                     # generated logs, ignored by Git
│   ├── Trace\                    # generated trace archive, ignored by Git
│   ├── LIMS\                     # generated model archives, ignored by Git
│   └── exchangAPI\               # generated exchangAPI logs, ignored by Git
├── Model\
├── bravocmd.exe
└── exchangAPI.exe
```

## Setup

Create a local config file:

```powershell
Copy-Item .\BRAVO.config.example.ps1 .\BRAVO.config.ps1
notepad .\BRAVO.config.ps1
```

Edit at least these values in `BRAVO.config.ps1`:

```powershell
ObjectName = "Object name"
ArchivePrefix = "example_prefix"
ArchivePassword = ""
BravoWebDir = "D:\Br-a-vo.web"
SlackMode = "errors_only"
SlackWebhookUrl = ""
```

`BRAVO.config.ps1` is intentionally ignored by Git. Do not commit real passwords, Slack webhook URLs, certificates, logs, or generated archives.

## Usage

Run the maintenance script from the `ARCHIV` directory:

```powershell
cd C:\LIMS\ARCHIV
.\BRAVO_MAINTENANCE.ps1
```

Force model restore regardless of schedule:

```powershell
.\BRAVO_MAINTENANCE.ps1 -ForceRestore
```

Disable the model file size comparison check for the current run:

```powershell
.\BRAVO_MAINTENANCE.ps1 -DisableSizeCheck
```

Send all Slack notifications for the current run:

```powershell
.\BRAVO_MAINTENANCE.ps1 -EnableAllSlack
```

Disable all Slack notifications for the current run:

```powershell
.\BRAVO_MAINTENANCE.ps1 -DisableAllSlack
```

Enable automatic shutdown after maintenance:

```powershell
.\BRAVO_MAINTENANCE.ps1 -AutoShutdown on
```

Disable automatic shutdown for the current run:

```powershell
.\BRAVO_MAINTENANCE.ps1 -AutoShutdown off
```

Enable the additional ARCHIV_LIMS step if `ARCHIV_LIMS.ps1` exists:

```powershell
.\BRAVO_MAINTENANCE.ps1 -ArchivLims on
```

Combine parameters when needed:

```powershell
.\BRAVO_MAINTENANCE.ps1 -ForceRestore -EnableAllSlack -AutoShutdown off
```

## Configuration notes

### Restore schedule

The restore schedule is controlled by:

```powershell
RestoreDay = 7
RestoreTime = "23:00"
```

`RestoreDay` uses numeric weekday values:

| Value | Day |
| ---: | --- |
| 1 | Monday |
| 2 | Tuesday |
| 3 | Wednesday |
| 4 | Thursday |
| 5 | Friday |
| 6 | Saturday |
| 7 | Sunday |

The script creates a daily marker file after a scheduled restore so the restore is not repeated multiple times on the same day.

### Retention

Retention is controlled by:

```powershell
ArchiveRetentionDays = 14
RestoreArchivesKeepCount = 1
LogRetentionDays = 180
```

- `ArchiveRetentionDays` controls old dated archive folders.
- `RestoreArchivesKeepCount` controls how many before/after restore archive sessions are kept.
- `LogRetentionDays` controls generated script logs, restore markers, file size CSV files, and archived exchangAPI logs.

### Slack modes

```powershell
SlackMode = "errors_only"
SlackWebhookUrl = ""
```

Allowed values:

| Value | Behavior |
| --- | --- |
| `none` | Do not send Slack notifications. |
| `errors_only` | Send only critical/error notifications. |
| `all` | Send success, informational, and error notifications. |

If `SlackWebhookUrl` is empty, Slack notifications are disabled automatically.

## What the maintenance script does

At a high level, the script:

1. Loads local configuration from `BRAVO.config.ps1`.
2. Checks Administrator rights, PowerShell version, OS version, and free disk space.
3. Stops Apache, exchangAPI, and BRAVO services/processes when present.
4. Checks `.md` model file sizes against the configured limit.
5. Creates a model archive before restore when restore is active.
6. Runs Bravo model restore through `bravocmd.exe`.
7. Compares model file sizes after restore and rolls back from the pre-restore archive if critical shrinkage is detected.
8. Creates a model archive after successful restore.
9. Moves trace, exchangAPI, Apache, and WWW logs into archive folders.
10. Restarts BRAVO, exchangAPI, and Apache.
11. Cleans up old logs and archives according to retention settings.
12. Sends a final Slack report when enabled.
13. Optionally shuts down the server if `AutoShutdown` is enabled.

## Exit codes

- `0` — completed without critical errors.
- `1` — completed with critical errors or failed a required pre-check.

## Safety notes

- Always test config changes on a non-production environment first.
- Keep `BRAVO.config.ps1` local only.
- Keep generated archives and logs out of Git.
- Before enabling scheduled restore, verify that `ArchivePassword`, `ArchivePrefix`, `RestoreDay`, `RestoreTime`, and available disk space are configured correctly.
- Before enabling `AutoShutdown`, make sure the script is running in an expected maintenance window.