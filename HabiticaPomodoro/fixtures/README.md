# Apple CLI regression fixtures

These are plain Swift compile/run fixtures, not XCTest or an additional test
framework. They do not build, install, or launch the app.

## Run

Requires macOS, Python 3.9+, Xcode Command Line Tools (`xcrun swiftc` and
`xcrun clang`), and a **non-root** account. No packages need installing.

From the repository root:

```sh
python3 HabiticaPomodoro/fixtures/run.py
python3 HabiticaPomodoro/fixtures/run.py --only file_monitor
python3 HabiticaPomodoro/fixtures/run.py --only qishi_audio
python3 HabiticaPomodoro/fixtures/run.py --only foreground_recovery --only dirty_reload
```

The work-directory base is `--work`, then `HERMES_SCRATCH`, then `TMPDIR`.
At least one must be provided; there is no implicit `/tmp` fallback. For example:

```sh
python3 HabiticaPomodoro/fixtures/run.py --only file_monitor \
  --work "$HOME/Library/Caches/HabiticaPomodoroFixtures"
```

The runner creates a new `tempfile.mkdtemp` directory on every invocation, even
when reusing a `--work` base. It refuses a repository, Documents, iCloud Drive,
or CloudStorage location (including symlink-resolved locations). Sources are
read from this checkout; generated sources, executables, preferences, synthetic
JSON, module caches, temporary files, and logs stay in the unique work root.
Nothing is generated in the checkout. Work roots are retained for diagnosis.

`--only` can be repeated. The default discovers `cases/*.swift`, except
the helper names in `CASE_HELPERS` (`audio_stubs`, `notification_stubs`, and
`activation_stubs`); it does not pretend an absent case ran. Selecting an absent
case, a compile error, a timeout, or a nonzero case exit is a failure. The default
compile timeout is 180 seconds per command and run timeout is 60 seconds per
case; override with `--compile-timeout` and `--run-timeout` if needed.

Each case prints its actual assertions. The runner prints a per-case outcome
and a final case count, exits nonzero on failure, and writes `results.json`.
`<case>/compile.log`, `<case>/result.log`, and (for native-delay cases)
`<case>/interposer-compile.log` contain the commands and complete child output.
`<case>/source-sha256.json` records the compiled snapshots' fingerprints.

## Real vs synthetic dependencies

The centralized `SOURCE_NAMES` tuple in `run.py` lists the real production
sources: `Managers.swift`, `HabiticaAPI.swift`, `PlantJournal.swift`,
`PomodoroEngine.swift`, `BlockNotificationManager.swift`, and
`BlockRewardManager.swift`. They are copied **byte-for-byte**, never rewritten,
and compiled with `-D DEBUG -swift-version 5`. Only the selected case is put into
generated `main.swift`, after the runner's isolation preflight, so Swift's
executable top-level rules are respected. Each executable is placed inside a
fresh `Probe.app/Contents/MacOS/` layout with a unique executable name and
non-user-app bundle ID. It is invoked **directly** as a CLI binary, never via
`open` or LaunchServices. Only the real `audio/qishi_presets.json` is copied to
`Contents/Resources/audio/`; there are no mp3s or DEBUG catalog substitutions.
The preflight verifies `Bundle.main` recognizes this bundle and resource, and
the unique ID separates its UserDefaults domain from the installed app.
Add shared source dependencies in that one tuple rather than changing
per-case commands.

- **`file_monitor`** exercises real managers, the real seven-file monitor,
  Foundation/Combine, serialization, background snapshots, and local writes.
  Its settings have `connectHabitica = false`, an empty UID, and an empty token.
  It never calls account/network or audio-playback methods. A native `read(2)`
  interposer delays only the explicitly selected synthetic JSON file under the
  injected fixture root, not all I/O. The test verifies the interposer's counter
  actually advances; losing DYLD injection cannot silently pass the heartbeat.
  Cases cover main-run-loop responsiveness, all seven stores (including block
  history), unchanged bytes, local-write races, corrupt-file retries, twenty
  coalesced requests and callback ordering, permission-induced failed saves,
  persistent dirty settings, the dirty three-file block group, and synchronous
  subscriber reentry. Permission failures are real local filesystem failures,
  not mocked save return values.
- **`qishi_audio`** compiles `cases/audio_stubs.swift` alongside
  the same production snapshots. Those `AVPlayer`/`AVAudioPlayer` transport
  doubles replace output/streaming, not application lifecycle logic. This case
  gets **no** native slow-read interposer. Selecting it without the case or its
  required stubs fails honestly. It uses the real bundled scene snapshot and
  covers same-scene/same-player pause and resume, late loop notifications,
  foreground resync, next-session nonrepeat, independent preview gains and
  teardown, and custom-track position continuity. The custom transport takes
  the existing catalog's URL as a token, not decodable sound; no fake MP3 is
  bundled and no actual audibility is claimed. The EOF transport also models
  an ended position that `play()` alone cannot leave: a queued notification
  after pause must seek/reset the loop without calling play during pause.
- **`foreground_recovery`** uses the real engine, Foundation scheduled timers,
  managers and scanner, plus the native read delay. It compiles the exact Mac
  `applicationDidBecomeActive` body and iOS activation-observer body into CLI
  adapters from fingerprinted source snapshots. It does not compile or launch
  either platform UI. Missing/ambiguous hook markers fail the runner. Tests
  cover arrived remote block/plant/histogram state before focus settlement,
  coalesced recovery, a real 1-second timer due during a 1.2-second read,
  completion-time wall clock, reset/pause/new phase, folder/A-B-A invalidation,
  elapsed focus-break-grace counting and heartbeat responsiveness.
  `audio_stubs.swift` prevents audio/network output;
  `notification_stubs.swift` shadows only notification delivery (real request
  and content value objects remain). `activation_stubs.swift` replaces the
  iOS grant/status owner: **no real bookmark or security-scoped API executes**.
  A folder change during recovery pauses the unchanged old phase rather than
  letting a later scheduled tick settle it into a different folder.
- **`dirty_reload`** uses all seven real stores, permission-induced failed
  writes and synthetic DEBUG A/B folders. It verifies successful explicit
  A-B-A replacements release only the discarded failed edit's dirty epoch,
  while bad JSON and synchronous subscriber/notification failed edits remain
  protected. Histogram same-path unsaved deltas are not considered discarded.
  The monitor's ordinary `consume`/scan path must not clear dirty ownership.

## Isolation and limits

Before any manager initializes, the generated preflight verifies Foundation's
home and Documents paths under the case's fresh `CFFIXED_USER_HOME` and sets
and verifies `PomodoroDataDir.isolatedDirectory`. `HOME` alone is not considered
sufficient. UserDefaults backups and the real widget bridge's file output are
therefore redirected to the synthetic home too. The case root, data root, and
run root are passed explicitly; there are no user-specific absolute paths or
date-dependent directory assertions. Inherited DYLD and fixture-control
variables are removed before children start. Compiler temporary files and both
Swift/Clang module caches have explicit work-root paths.

A case receives its data directory as `CommandLine.arguments[1]`, synthetic
home as `[2]`, and case work directory as `[3]`. Environment variables
`POMO_FIXTURE_RUN_ROOT`, `POMO_FIXTURE_CASE_ROOT`, and `POMO_FIXTURE_DATA_ROOT`
identify the corresponding canonical scratch paths. A new case must seed safe
settings before constructing managers: Habitica disabled, empty credentials,
no account calls. Audio cases must use the provided fake transport, not real
sound output. This is fixture-level isolation, **not an OS security sandbox**.

No `.env`, live settings, credentials, or synced user JSON are read. No network
request is part of these fixtures. Passing them establishes isolated regression
logic, not real FileProvider/iCloud transport behavior, cold-start/explicit-save
nonblocking behavior, authenticated Habitica sync, audio audibility, or live
Mac/iOS UI/device correctness. Manual user-facing runtime, online, and
cross-device acceptance remain separate checks.

Synthetic A/B selection via `PomodoroDataDir.isolatedDirectory` is not an iOS
folder grant, a security-scoped lifetime test, or a real user-folder migration.
