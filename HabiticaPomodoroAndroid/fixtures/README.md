# HabiticaPomodoroAndroid fixture harness

Offline compile-and-run harness for the Top3 cloud-sync engine. It compiles the
**real production sources** against **stub plumbing** and runs behavior cases
one by one, printing `CASE <name> EXIT=<code>` per case. It is deliberately NOT
wired into Gradle (no plugins, no test dependencies in build files) — it lives
beside the module as plain source + one Python script.

## Run

```sh
export JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
python3 HabiticaPomodoroAndroid/fixtures/run.py            # full suite (from repo root)
python3 run.py --only d1_03_markerless_consumption_retires # single case
python3 run.py --list                                      # list cases
python3 run.py --fresh                                     # wipe work dir first
```

Exit code: 0 = all cases pass, 1 = at least one case failed (a case that fails
to **compile** also counts as `EXIT=1` — that is the RED signal for TDD cases
targeting not-yet-existing production API).

Requirements: a JDK **17–21** (`JAVA_HOME` or `java` on PATH) and Python 3.
JDK 22+ is NOT supported: kotlin-compiler-embeddable 2.0.21 crashes on newer
class-file versions (`IllegalArgumentException: 27` from `JavaVersion.parse`).
No network is needed when the toolchain jars resolve from the local Gradle cache;
otherwise run.py downloads them once (pinned versions) into the toolchain dir.

## What gets compiled

Production (real files, unmodified):

- `app/src/main/java/com/habitica/pomodoro/data/Models.kt`
- `app/src/main/java/com/habitica/pomodoro/data/BlockModels.kt`
- `app/src/main/java/com/habitica/pomodoro/data/TopThreeCloudSync.kt`
- `app/src/main/java/com/habitica/pomodoro/data/LocalStore.kt`
- `app/src/main/java/com/habitica/pomodoro/engine/PomodoroViewModel.kt`

Substituted plumbing (`stubs/`, HTTP 0 by construction — there is no networking
code in the harness at all):

- `habitica_api_stub.kt` — `data.HabiticaAPI` replaced by a scriptable in-memory
  substitute (cloud todo list, delete/create/tag outcomes, recorded call log).
- `service_stubs.kt` — `PomodoroTimerService` / `BlockReminderReceiver` no-ops
  with call logs.
- `android_stubs.kt`, `android_app_stubs.kt`, `android_log_stub.kt` — minimal
  `Context`/`Application`/`SharedPreferences`/`Log`.
- `androidx_lifecycle.kt` — `AndroidViewModel` + `viewModelScope` backed by
  `Dispatchers.Unconfined`, so every VM coroutine (sync, delete, retry) runs
  **synchronously and deterministically** inside the calling case.

Real libraries used from the pinned toolchain: `kotlin-stdlib 2.0.21`,
`kotlinx-coroutines-core-jvm 1.7.3`, **real `org.json:json:20240303`** (JSON
semantics identical to the app's declared dependency), compiled with
`kotlin-compiler-embeddable 2.0.21` (`K2JVMCompiler`).

The Compose UI (`ui/*.kt`) is NOT compiled here. Per repo convention the UI is
thin over `StateFlow` state: cases assert on VM state (counts, store contents,
error fields), not rendering. UI edits are additionally compile-checkable
against the cached Compose jars + compose compiler plugin outside this harness.

## Cases

`cases/Support.kt` provides fake fixture credentials, temp app dirs, JSON
seeding, `newVm(...)` (resets all stubs, then constructs the VM — init runs the
full loadAll cycle synchronously) and assertion helpers. Each other `*.kt` file
is one case with a `fun main()`; uncaught `AssertionError` = `EXIT=1`.

Suites:

- `smoke_harness_selftest` — plumbing self-test.
- `d1_01..d1_17` — the D1 suite (deletedCloudIdMarkers association fix):
  marker lifecycle (enqueue → unique-match link → retirement), marker-less
  queue consumption retiring the linked marker atomically, both enqueue points
  (deleteTask + lost-POST binding), archive-copy exemption, delete protection,
  quarantine block/exempt, merge bind/ambiguity, JSON round-trip of all four
  bookkeeping collections, owner partition isolation, tombstone-before-delete
  ordering, transient-failure recovery loop.
- `fix1_*` — P0 manual cleanup of orphaned create markers
  (`clearQuarantinedCreateMarkers`): clears markers+links for the current owner
  partition only; queue/origins/history/other partitions untouched; unblocks
  quarantine afterwards.
- `fix2_*` — D2 write-failure visibility: blocked data dir surfaces
  `UiState.persistenceError` (Top3 + settings paths), successful save clears it.
- `fix3_*` — D4 error clearing: clean successful refresh clears a stale
  `topThreeSyncError`; guards keep it while quarantine conflict, pending
  markers, delete protection or a persistence failure is active.
- `fix4_01` — D3 characterization pin: legacy first-owner adoption of
  deletedCloudIds/origins (documented decision, comment-only change).

## Invariants the suite pins

1. Explicit delete intents are sacred: `deletedCloudIds` /
   `deletedCloudTaskOrigins` are only drained by a confirmed (404 read-back)
   cloud delete — never by cleanup or merge paths.
2. A queue entry consumed without a marker must still retire its linked
   `deletedCreateMarkers` entry in the same atomic save (via
   `deletedCloudIdMarkers`), or the marker orphans forever (D1).
3. Tombstone persists BEFORE the network delete is attempted.
4. Delete protection: a queued id bound to an active local task is never
   deleted; the archive copy (original UUID, `movedToToday`) is exempt.
5. Quarantine: inbound todos matching a pending create-marker signature are
   neither imported nor bound while the marker lives; known (bound) ids are
   exempt; confirmed cleanup unblocks them.
6. Ambiguous create matches never bind and never re-POST.
7. Owner partitions (UID + canonical HTTPS API root) never leak queues,
   markers, links or history into each other.
8. Store JSON round-trips losslessly through the real LocalStore/org.json.
9. Disk write failures must surface in `UiState.persistenceError` (D2);
   `topThreeSyncError` clears only on a clean successful cycle (D4).

## Layout / hygiene

- Work + logs: `--work DIR`, else `$POMO_FIXTURES_WORK`, else
  `$TMPDIR/pomo-fixtures-work`, else `fixtures/.work/` (gitignored). JVM tmpdir
  is pinned under the work dir; nothing is ever written to `/tmp` or to real
  user data (`~/Documents/.habitica-pomodoro`, device data).
- Toolchain jars: `--toolchain DIR`, else `fixtures/.toolchain/` (gitignored),
  else `~/.gradle/caches/modules-2/files-2.1`, else `~/.m2/repository`, else
  Maven Central download (pinned). Per-case compile+run logs land in
  `<work>/logs/<case>.log`.
- Fake credentials only (`Support.kt`); cases must never print or use real
  UID/token values.
