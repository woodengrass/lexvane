# M0 T004 — decision notes (baseline v1.7)

Covers still-open choices from T001-T003. Details stay in Toolchain.md (T001), Persistence.md (T002), Xcode-Tooling.md (T003).

## Decided

- Naming: display `lexvane`, target/scheme `Lexvane`, entry `LexvaneApp`, bundle `app.lexvane`. Reason: matches planning naming rule and proves identity test.
- Min iOS 18.0, Swift 6 mode, full concurrency checks. Reason: modern baseline with no warning bypasses; verified on Xcode 27.0, runtime iOS 27.0.
- Persistence direction: disposable `probe_values` int key/value table, caller-supplied file URL, `user_version` 0 to 1 in one transaction. Reason: smallest proof of SQL read/write plus a migration path.
- Dependencies: zero third-party, system SQLite via `import SQLite3`. Reason: no package/version choice needed for a probe; GRDB deferred to product phase when queries grow.
- Entry point creates no product database. Reason: keeps probe UI-independent and throwaway.

## Deferred (named, not decided)

- Content-vs-user DB layout, production migrations, WAL/concurrency policy, backup/restore. Reason: probe table is not that architecture (Persistence.md).
- Time/ID conventions (study-day start, UTC storage, stable event IDs). Status: deferred. Reason: probe stores ints only, no events yet; real rules land with T005 IDs and T011 events.
- iOS 18 device/runtime test, crash/power-loss durability. Reason: no such device here; only Simulator proven.

## Xcode/MCP wiring

- T003 check found no MCP and proved CLI fallback (`xcodebuild build ... generic/platform=iOS Simulator`). Reason: honest record, binary present but session-unbridged.
- Post-check, per explicit user request, `mcp.xcode` via `~/.config/opencode/xcode-mcp.sh` (DEVELOPER_DIR wrapper) was merged alongside the two JetBrains entries. Reason: keep merge-only config, enable agent bridge.
- Remaining manual step: Xcode Settings > Intelligence > Allow external agents, keep `Lexvane.xcodeproj` open, restart OpenCode. Reason: handshake needs a live session.

## Non-goals respected

No sync, no Android, no FSRS/complex algorithms, no learning/words schema, no brand visuals, no signing. Reason: T004 acceptance forbids pre-engineering these.
