# Stage 13 — Runtime try/finally analysis

## Призначення

Цей документ фіксує analysis-only етап перед можливим впровадженням runtime try/finally wrapper у BRAVO maintenance-скрипт.

У цьому етапі runtime-код не змінюється.

Мета — зафіксувати поточну карту exit/throw/cleanup шляхів і визначити, чи безпечно переходити до централізованого cleanup-механізму.

## База аналізу

- Branch: stage13-runtime-try-finally-analysis
- Base: main після tag runtime-ci-stable-2026-05-31
- Stable commit before analysis: 18ccc4f
- Runtime file: src/99-Main.ps1

## Поточна карта exit / throw

### До створення runtime mutex

До створення Global\\BRAVO_MAINTENANCE mutex у src/99-Main.ps1 є ранні validation/configuration шляхи:

- ArchivePasswordEncryptHeaders validation: exit 1;
- ArchivePasswordEnabled validation: exit 1;
- SetupCredentials: exit 0;
- InstallScheduledTask: exit 0;
- archive password bootstrap: throw;
- archive password missing: throw;
- AutoShutdown validation: exit 1;
- ArchivLims validation: exit 1.

Ці шляхи не потребують Release-BravoMaintenanceMutex, бо mutex ще не створений або не захоплений.

### Створення runtime mutex

Runtime mutex створюється і захоплюється перед основною runtime-частиною.

Cleanup helper:

Release-BravoMaintenanceMutex

Він уже перевіряє наявність mutex і стан BravoMaintenanceMutexAcquired, тому повторний виклик має бути безпечним.

### Після mutex, але до Initialize-BravoProgressState

Після Stage 5.2 такі ранні помилки вже звільняють runtime mutex перед exit 1:

- OS version error;
- запуск не з папки ARCHIV;
- помилка створення директорії логів.

У цих блоках Close-BravoProgressState не викликається, бо progress state ще не ініціалізований.

### Після Initialize-BravoProgressState

Після Stage 3–5 основні явні completion/error шляхи вже мають cleanup:

- ShowProgressState: Wait-BravoInteractiveExit, Release-BravoMaintenanceMutex, exit 0;
- HealthCheckOnly: Close-BravoProgressState, Wait-BravoInteractiveExit, Release-BravoMaintenanceMutex, exit healthExitCode;
- Check-FreeSpace failure: Close-BravoProgressState CompletedWithErrors, Release-BravoMaintenanceMutex, exit 1;
- final block: Close-BravoProgressState, Wait-BravoInteractiveExit, Release-BravoMaintenanceMutex, exit exitCode.

## Висновок по full try/finally wrapper

На поточному етапі не рекомендується одразу впроваджувати великий try/finally wrapper навколо всього src/99-Main.ps1.

Причини:

- у файлі є різні класи exit-шляхів: до mutex, після mutex до progress state, після progress state;
- частина early exit не повинна викликати progress state cleanup;
- PowerShell exit у try/finally може змінити порядок завершення і поведінку інтерактивного wait;
- великий wrapper збільшить ризик регресії у scheduler/interactive режимах;
- після Stage 5 основні явні exit-шляхи після mutex уже захищені.

## Безпечні наступні варіанти

### Варіант A — Controlled exit helper

Додати helper-функцію для контрольованого завершення після mutex acquisition, наприклад:

Invoke-BravoControlledExit

І поступово замінювати явні exit-шляхи після mutex на цей helper.

Переваги:

- менший ризик;
- чіткі параметри: exit code, close progress state чи ні, wait чи ні;
- простіше тестувати по одному exit-path.

### Варіант B — Narrow try/finally тільки після progress initialization

Обгорнути тільки основний runtime-блок після Initialize-BravoProgressState, не зачіпаючи preflight/configuration logic.

Переваги:

- не зачіпає ранні validation/config paths;
- progress state уже існує;
- cleanup scope зрозуміліший.

Ризики:

- треба акуратно перевірити взаємодію з Wait-BravoInteractiveExit;
- треба уникнути подвійного Close-BravoProgressState з неправильним статусом;
- треба чітко обробити criticalErrorOccurred.

### Варіант C — Analysis-only залишити як фінальне рішення

Поки що нічого не змінювати, бо явні exit-шляхи вже закриті точковими змінами Stage 3–5.

Це найменш ризиковий варіант, якщо немає нових runtime-збоїв.

## Рекомендація

Рекомендований наступний технічний крок — не full try/finally wrapper, а проектування Invoke-BravoControlledExit helper.

Helper має приймати параметри:

- ExitCode;
- CloseProgressState;
- ProgressStatus;
- WaitInteractive;
- ReleaseMutex.

Після цього можна точково перевести ShowProgressState, HealthCheckOnly, Check-FreeSpace failure і final block на єдиний механізм завершення.

## Що не змінювалось

- src/99-Main.ps1 не змінювався;
- Build-BRAVO-Monolith.ps1 не змінювався;
- GitHub Actions workflow не змінювались;
- runtime behavior не змінювався.

## Перевірка

Цей етап не потребує build validation, бо змінюється тільки analysis-документ.

Перед наступними runtime-змінами бажано знову виконати:

.\\Build-BRAVO-Monolith.ps1 -Clean -CreateSha512

## Статус

Stage 13 є analysis-only PR.

Рішення про впровадження controlled exit helper або narrow try/finally wrapper має бути окремим Stage 14.
