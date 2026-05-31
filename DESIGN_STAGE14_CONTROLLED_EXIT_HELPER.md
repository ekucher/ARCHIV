# Stage 14 — Controlled Exit Helper Design

## Призначення

Цей документ описує дизайн helper-функції Invoke-BravoControlledExit для майбутнього контрольованого завершення BRAVO maintenance-скрипта.

Stage 14 є design-only етапом. Runtime-код у цьому етапі не змінюється.

## База

- Branch: stage14-controlled-exit-helper-design
- Base: main після PR #51
- Current main: e7c80a1
- Попередній analysis document: ANALYSIS_STAGE13_RUNTIME_TRY_FINALLY.md

## Ціль helper-а

Invoke-BravoControlledExit має централізувати повторювану exit-послідовність після runtime mutex acquisition:

- опційне закриття progress state;
- опційний interactive wait;
- звільнення runtime mutex;
- завершення процесу з потрібним exit code.

Мета не в тому, щоб одразу обгорнути весь файл у try/finally, а в тому, щоб поступово прибрати ручне дублювання cleanup-послідовностей у безпечних місцях.

## Запропонована сигнатура

Invoke-BravoControlledExit parameters:

- ExitCode: int;
- Reason: string;
- LogMessage: string optional;
- CloseProgressState: switch;
- ProgressStatus: Completed | CompletedWithErrors | Interrupted;
- WaitInteractive: switch;
- ReleaseMutex: switch, default true;
- TaskUserName: string;
- PreserveExistingProgressState: switch optional.

## Базова поведінка

Helper має виконувати дії в такому порядку:

1. Якщо LogMessage заданий — записати повідомлення через Write-Log або Write-Host залежно від доступності logging layer.
2. Якщо CloseProgressState увімкнений — викликати Close-BravoProgressState з переданим ProgressStatus.
3. Якщо WaitInteractive увімкнений — викликати Wait-BravoInteractiveExit з TaskUserName і ExitCode.
4. Якщо ReleaseMutex увімкнений — викликати Release-BravoMaintenanceMutex.
5. Виконати exit ExitCode.

## Обмеження

Helper не повинен автоматично закривати progress state, якщо CloseProgressState явно не заданий.

Причина: у частині early-exit шляхів progress state ще не ініціалізований. Автоматичне закриття progress state без явного прапора може створити регресію.

Helper не повинен автоматично викликати Wait-BravoInteractiveExit, якщо WaitInteractive явно не заданий.

Причина: scheduler mode і non-interactive запуск не повинні отримати несподівану паузу.

## Перші кандидати для майбутньої міграції

У Stage 15 або пізніше можна точково перевести такі шляхи:

### ShowProgressState

Поточна послідовність:

- Show-BravoProgressState;
- Wait-BravoInteractiveExit;
- Release-BravoMaintenanceMutex;
- exit 0.

Майбутня форма:

Invoke-BravoControlledExit -ExitCode 0 -Reason ShowProgressState -WaitInteractive -ReleaseMutex

Progress state тут не потрібно закривати.

### HealthCheckOnly

Поточна послідовність:

- Invoke-BravoHealthCheck;
- Close-BravoProgressState Completed або CompletedWithErrors;
- Send-FinalReport;
- Wait-BravoInteractiveExit;
- Release-BravoMaintenanceMutex;
- exit healthExitCode.

Майбутня форма має врахувати, що Send-FinalReport виконується до controlled exit.

### Check-FreeSpace failure

Поточна послідовність:

- Write-Log error;
- Close-BravoProgressState CompletedWithErrors;
- Release-BravoMaintenanceMutex;
- exit 1.

Майбутня форма:

Invoke-BravoControlledExit -ExitCode 1 -Reason CheckFreeSpaceFailed -CloseProgressState -ProgressStatus CompletedWithErrors -ReleaseMutex

WaitInteractive тут не обов'язковий, якщо поточна поведінка його не передбачає.

### Final block

Поточна послідовність:

- Close-BravoProgressState Completed або CompletedWithErrors;
- Write-Log final messages;
- Send-FinalReport;
- Wait-BravoInteractiveExit;
- Release-BravoMaintenanceMutex;
- exit exitCode.

Майбутня форма має не змінити порядок final log/report/wait.

## Шляхи, які не слід переводити першими

Не рекомендується на першому етапі переводити:

- validation exit до створення mutex;
- SetupCredentials exit;
- InstallScheduledTask exit;
- archive password bootstrap throw;
- mutex acquisition failure exit 2;
- duplicate run blocked exit 2.

Причина: ці шляхи або відбуваються до runtime cleanup scope, або мають окрему preflight/bootstrap семантику.

## Ризики

- Подвійний Close-BravoProgressState з неправильним статусом;
- несподіваний Wait-BravoInteractiveExit у scheduler mode;
- зміна exit code;
- зміна порядку Send-FinalReport і final log messages;
- занадто широкий helper може приховати різницю між preflight і runtime завершенням.

## Рекомендований план Stage 15

Stage 15 має бути runtime-code PR, але максимально вузький:

1. Додати Invoke-BravoControlledExit після Release-BravoMaintenanceMutex або поруч з runtime helper functions.
2. Не міняти всі exit одразу.
3. Перевести тільки ShowProgressState або тільки Check-FreeSpace failure як перший proof-of-concept.
4. Виконати build validation.
5. Перевірити diff вручну.

## Що не змінювалось у Stage 14

- src/99-Main.ps1 не змінювався;
- Build-BRAVO-Monolith.ps1 не змінювався;
- GitHub Actions workflow не змінювались;
- runtime behavior не змінювався.

## Статус

Stage 14 є design-only PR.

Реалізація Invoke-BravoControlledExit має бути окремим Stage 15.
