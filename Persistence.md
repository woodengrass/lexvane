# M0 T002 — local persistence proof

Verified 2026-10-11, on top of the T001 foundation. This completes T002,
not all of M0. Toolchain.md remains the historical T001 report.

## Decision and dependency versions

Use **Apple's system SQLite through `import SQLite3`**, with **zero third-party
dependencies**. No SwiftPM packages are declared, so no `Package.resolved` is
needed or fabricated. Reproduce the verification environment with Xcode **27.0
(27A266a)**, Swift **6.4 (swiftlang-6.4.0.34.1)** in Swift 6 language mode, and
the iOS **27.0 Simulator SDK/runtime**; minimum deployment remains iOS 18.0.
See Toolchain.md for the existing toolchain probes.

The standalone Swift prototype actually migrated an empty on-disk database,
saved `(7, 42)`, closed it, reopened it, reread `42`, deleted the row, and removed
the temporary directory. It exited **0** with `PROTOTYPE SUCCEEDED`.
The host's system SQLite was **3.51.0**, source ID:
`2025-06-12 13:14:41 f0ca7bba1c5e232e5d279fad6338121ab55af0c8c68c84cdfb18ba5114dcaapl`.
The actual iPhone Simulator test reported SQLite **3.54.0**, source ID:
`2026-04-09 12:25:13 8fa8248e303219400c646a885e36dfc52eae33d83f4412e3f369b2be5373aapl`.
System SQLite is supplied by the OS, not independently package-pinned; these
are observed versions, not a promise that every supported iOS has that version.
There is no floating third-party dependency resolution.

Direct SQLite is the smallest proof of transparent SQL read/write and a migration
path. GRDB remains a sensible candidate when product queries and migrations grow,
but adds a package/version decision unnecessary for this probe. SwiftData/Core
Data add model machinery, and a preferences/file-only store would not prove the
SQL migration direction. Those alternatives were considered, not implemented or
benchmarked; only the direct SQLite prototype was run.

## Scope and migration path

`Lexvane/SQLiteProbeStore.swift` is UI-independent and stores only disposable
integer key/value fixtures in `probe_values`. The caller supplies the file URL;
the app entry point is unchanged and does not create a product database.
Each operation opens and closes a connection and finalizes its bound statements.
An explicit transaction creates the fixture table and advances `PRAGMA
user_version` from 0 to 1 atomically. Version 1 reopens without recreating it;
unknown versions are rejected. Errors roll back instead of deleting/rebuilding
the file. Future migrations can extend the version switch transactionally, or
move to GRDB without abandoning SQLite files.

Three new tests in the existing `LexvaneTests` target cover:
- Save, reread using a different helper/connection, update, delete, reread absence.
- Failed initial migration preserves the existing row and schema version.
- Newer schema rejection leaves version 2 unchanged and creates no probe table.

Every test uses a unique temporary directory and removes it even after a thrown
error; cleanup failure fails the test. No learning data, words/exams schema,
algorithms, FSRS, sync, or UI features are added. Content-versus-user database
layout, production migrations, concurrency/WAL policy, backup and restore remain
undecided for later tasks; this disposable table is not that architecture.
Planning v1.7 and all policy/content/data versions are unchanged.

## Exact verification commands and results

From the repository root, in zsh. Logs/DerivedData/result bundle are outside the
repo. `pipefail` preserves failures; use a fresh result-bundle path on reruns.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available
```
Exit **0**; selected iPhone 18 Pro, iOS 27.0,
`AA1E0570-12E0-4DCE-B33D-DD8EDD491514` (available and booted).

```sh
set -o pipefail && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift -swift-version 6 /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T002-prototype.swift 2>&1 | DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tee /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T002-prototype.log
```
The exploratory script is a temporary artifact, not required for reproduction;
the checked-in Simulator tests reproduce and extend its persistence proof.

```sh
set -o pipefail && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Lexvane.xcodeproj -scheme Lexvane -configuration Debug -destination 'platform=iOS Simulator,id=AA1E0570-12E0-4DCE-B33D-DD8EDD491514' -derivedDataPath /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T002-DerivedData 2>&1 | DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tee /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T002-build.log
```
Exit **0**, `** BUILD SUCCEEDED **`.

```sh
set -o pipefail && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Lexvane.xcodeproj -scheme Lexvane -configuration Debug -destination 'platform=iOS Simulator,id=AA1E0570-12E0-4DCE-B33D-DD8EDD491514' -derivedDataPath /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T002-DerivedData -resultBundlePath /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T002-tests.xcresult -parallel-testing-enabled NO 2>&1 | DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer tee /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T002-test.log
```
Exit **0**; actual output:
```text
Test Case '-[LexvaneTests.LexvaneTests testPersistenceFailedMigrationPreservesExistingData]' passed (0.004 seconds).
Test Case '-[LexvaneTests.LexvaneTests testPersistenceRejectsNewerSchemaWithoutDowngrading]' passed (0.001 seconds).
Test Case '-[LexvaneTests.LexvaneTests testPersistenceSaveReopenReadAndDelete]' passed (0.005 seconds).
Executed 4 tests, with 0 failures (0 unexpected) in 0.011 (0.014) seconds
** TEST SUCCEEDED **
```

Warnings were not suppressed: Xcode emitted the existing AppIntents metadata
warning; Simulator emitted launch-measurement messages. The migration-failure
test intentionally emitted SQLite's `table probe_values already exists` message.
LSP reported no diagnostics for the helper, but SourceKit could not resolve
`XCTest` for the hosted test file. The real Xcode test target compiled and ran;
no editor/tooling configuration was changed to hide that limitation. No physical
device or iOS 18 runtime was tested, and crash/power-loss durability is not proven.

Only the helper, existing test file, project source membership, and this note
are changed for T002. Existing untracked T001 files and `.omo/` are preserved;
`planning/`, OpenCode/OMO configuration and Toolchain.md are untouched. No commit.
Next in the M0 sequence: T003 (Xcode tooling integration), then T004 decisions.
