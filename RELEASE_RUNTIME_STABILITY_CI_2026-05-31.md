# Release Snapshot — Runtime Stability and CI

Дата: 2026-05-31

## Stable point

- Branch: main
- Base commit: 6371e7e
- Merge PR: #49
- Repository state: clean після pull на main

## Scope

Цей release snapshot фіксує стабільну точку після серії змін Runtime Stability та GitHub Actions CI.

У scope входять:

- runtime mutex cleanup;
- progress state failure handling;
- early setup error cleanup;
- GitHub Actions diagnostics;
- CI workflow deduplication;
- manual CI verification;
- зведений changelog index.

## Completed stages

| Stage | Тема | PR | Статус |
| --- | --- | --- | --- |
| Stage 5.1 | Progress state close on free-space failure | #44 | Done |
| Stage 5.2 | Early setup error mutex release | #46 | Done |
| Stage 6 | GitHub Actions diagnostics | #47 | Done |
| Stage 7 | CI workflow deduplication | #48 | Done |
| Stage 8 | Manual CI verification | workflow_dispatch | Done |
| Stage 9 | Runtime/CI changelog index | #49 | Done |

## Runtime behavior after release

Після внесених змін maintenance-скрипт BRAVO контрольованіше завершується у runtime-шляхах:

- фінальне завершення звільняє runtime mutex;
- HealthCheckOnly-завершення звільняє runtime mutex;
- ShowProgressState-завершення звільняє runtime mutex;
- Check-FreeSpace failure закриває progress state як CompletedWithErrors і звільняє runtime mutex;
- ранні помилки після створення mutex, але до Initialize-BravoProgressState, звільняють runtime mutex без спроби закривати progress state.

## CI behavior after release

Після Stage 6–7 GitHub Actions розділено чіткіше:

- bravo-build-validation.yml є основним workflow для перевірки src/*.ps1, збірки моноліту і перевірки generated output;
- powershell-syntax.yml є легким workflow для перевірки root BRAVO_MAINTENANCE.ps1, якщо файл є в корені;
- після checkout workflow показують діагностику repository root, Git HEAD і ключових файлів;
- дублювання build generated monolith прибрано з powershell-syntax.yml.

## Verification

Локальні перевірки виконувалися через:

.\Build-BRAVO-Monolith.ps1 -Clean -CreateSha512

Manual GitHub Actions verification:

- Workflow: BRAVO Build Validation
- Event: workflow_dispatch
- Branch: main
- Commit: 6047b04
- Result: Success
- Duration: 22s

Поточний release snapshot створено після merge PR #49, на main commit 6371e7e.

## Known warnings

- GitHub Actions показує warning про deprecated Node.js 20 actions.
- Це попередження не ламає build.
- Майбутній етап може оновити actions до версій, що працюють на новішому Node.js runtime.

## Related documentation

- CHANGELOG_RUNTIME_STABILITY_AND_CI.md
- CHANGELOG_STAGE5_PROGRESS_STATE_FAILURE_HANDLING.md
- CHANGELOG_STAGE5_EARLY_ERROR_MUTEX_RELEASE.md
- CHANGELOG_STAGE6_GITHUB_ACTIONS_DIAGNOSTICS.md
- CHANGELOG_STAGE7_CI_WORKFLOW_DEDUPLICATION.md

## Release decision

Цю точку можна вважати стабільною базою для наступних робіт над BRAVO maintenance automation.

Рекомендовано використовувати main commit 6371e7e як базовий reference для подальших stage-гілок.

## Notes

Цей документ не змінює runtime-код, build-скрипти або GitHub Actions.

Тимчасові helper/patch-скрипти та backup-директорії не входять у коміти.
