# Lexvane — M0 T001 foundation

Verified on 2026-10-11 with the real Xcode installation, not CommandLineTools.
Open `Lexvane.xcodeproj`, select the shared `Lexvane` scheme and an iPhone
Simulator, then Run. The app deliberately presents an empty SwiftUI window.

## Decisions

- Project/target/scheme: `Lexvane`; entry: `LexvaneApp`; display name: `lexvane`.
- Bundle ID: `app.lexvane` (tests: `app.lexvane.tests`). This is a sensible
  development identifier, not a claim that an App Store identifier is registered.
- Minimum iOS: **18.0**, for a modern native baseline without requiring the newest
  OS. The current SwiftUI APIs are available at this deployment target, as verified
  by compilation. Runtime verification used iOS 27.0; an iOS 18 device/runtime was
  not available and has not been tested.
- Swift **6 language mode**, with complete concurrency checking in both build
  configurations; no concurrency bypasses or warning suppression.
- iPhone only; no third-party dependencies, persistence, learning engine, sync,
  account system, or visual brand decisions. No signing team configured.
- Hosted XCTest target has one identity smoke test (bundle ID and display name).
  This proves discovery, app-host launch, and assertions rather than product logic.
- This completes **T001 only**, not all of M0. T002 persistence is the next task.
  Specification baseline: planning v1.7; no policy/data versions changed.

## Versions and exact probe commands

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -version
```
```text
Xcode 27.0
Build version 27A266a
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift --version
```
```text
swift-driver version: 1.168.6 Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)
Target: arm64-apple-macosx26.0
```

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -showsdks
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl list devices available
```
Relevant output: `iOS 27.0 -sdk iphoneos27.0` and
`Simulator - iOS 27.0 -sdk iphonesimulator27.0`.
Test/run device: iPhone 18 Pro, iOS 27.0,
`AA1E0570-12E0-4DCE-B33D-DD8EDD491514`.

## Exact build/test commands and results

Executed from the repo root in zsh. Temporary output is kept outside the repo;
`pipefail` preserves xcodebuild's exit code while `tee` captures full stdout/stderr.

```sh
set -o pipefail && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Lexvane.xcodeproj -scheme Lexvane -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T001-DerivedData 2>&1 | tee /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T001-build.log
```
Result: exit 0, `** BUILD SUCCEEDED **` (arm64 and x86_64 Simulator).

```sh
set -o pipefail && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Lexvane.xcodeproj -scheme Lexvane -configuration Debug -destination 'platform=iOS Simulator,id=AA1E0570-12E0-4DCE-B33D-DD8EDD491514' -derivedDataPath /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T001-DerivedData -resultBundlePath /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T001-tests.xcresult -parallel-testing-enabled NO 2>&1 | tee /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T001-test.log
```
Result: exit 0; exact output excerpt:
```text
Test Case '-[LexvaneTests.LexvaneTests testAppIdentity]' passed (0.002 seconds).
Executed 1 test, with 0 failures (0 unexpected) in 0.002 (0.004) seconds
** TEST SUCCEEDED **
```

A generic destination is valid for building, but executing tests needs a concrete
Simulator. On another machine choose an available iPhone from `simctl list` and
replace the UUID. Use a fresh result-bundle path for subsequent test runs.
Full output logs and the `.xcresult` are at the temporary paths in these commands.
Xcode emitted its unsuppressed tooling warning:
`Metadata extraction skipped, no AppIntents.framework dependency found`.
No AppIntents functionality belongs in this empty app.

## Standalone Simulator launch

An initial `simctl launch` failed with code 405 (`Unable to lookup in current
state: Shutdown`): the test runner had shut down the device. Then executed:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl boot AA1E0570-12E0-4DCE-B33D-DD8EDD491514 && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl bootstatus AA1E0570-12E0-4DCE-B33D-DD8EDD491514 -b && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl install AA1E0570-12E0-4DCE-B33D-DD8EDD491514 /var/folders/dt/lt4qz2hd6qgdzj_0lkh72hxw0000gn/T/opencode/Lexvane-T001-DerivedData/Build/Products/Debug-iphonesimulator/Lexvane.app && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl launch AA1E0570-12E0-4DCE-B33D-DD8EDD491514 app.lexvane
```
Boot completed, install succeeded, launch exited 0 and returned:
```text
app.lexvane: 22409
```

No physical-device build, archive, distribution signing, or product UI QA was
performed. Existing `planning/`, `.omo/`, and root `.gitignore` remain untouched.

Final `git status --short` showed the intended new `Lexvane.xcodeproj/`,
`Lexvane/`, `LexvaneTests/`, and `Toolchain.md`, plus the existing untracked
`.omo/` directory observed at initial inspection. It was not removed or hidden
to manufacture a clean status. Expanded status showed only the six intended
new foundation files outside `.omo/`; no tracked files were modified. No commit
was created.
