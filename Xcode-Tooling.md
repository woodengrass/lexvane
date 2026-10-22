# M0 T003 — OpenCode/OMO to Xcode wiring (read-only check + CLI fallback proof)

Verified 2026-10-11. This completes T003's record requirement, not all of M0.
No OpenCode/OMO config was modified; every config below was READ ONLY.
`planning/` and `.omo/` are untouched. `Toolchain.md` (T001) and
`Persistence.md` (T002) remain the historical reports.

## 1. Existing OpenCode/OMO config files found (exact paths)

| Path | Status | Content summary |
|---|---|---|
| `/Users/jason/code/lexvane/opencode.json` | absent (repo root has no `opencode.*`) | — |
| `/Users/jason/code/lexvane/opencode.jsonc` | absent | — |
| `/Users/jason/code/lexvane/.opencode/` | absent (`ls` → "No such file or directory") | — |
| `/Users/jason/.config/opencode/opencode.jsonc` | PRESENT, unmodified | `plugin: ["oh-my-openagent@latest"]`, `lsp: true`, `mcp` has exactly two entries: `jetbrains-webstorm` and `jetbrains-pycharm` (both `type: local`, via `/Users/jason/.config/opencode/jetbrains-mcp.sh`, `enabled: true`, `timeout: 30000`). No Xcode entry. |
| `/Users/jason/.config/opencode/jetbrains-mcp.sh` | present, only read via listing | launcher referenced by the two entries above |
| `/Users/jason/.config/opencode/oh-my-openagent/` | present (dir) | OMO plugin install referenced by `opencode.jsonc` |
| `/Users/jason/code/lexvane/.omo/` | present (`drafts/`, `run-continuation/` only) | read-only listing; nothing added or edited |
| `/Users/jason/code/lexvane/planning/` | present, untouched | sources below |

Merge-only mindset honored: nothing was appended to any config; no new MCP
was registered. Any future Xcode MCP must merge a single new key under `mcp`
in `~/.config/opencode/opencode.jsonc`, never rewrite the file.

## 2. Is an Xcode MCP (e.g. `xcrun mcpbridge`) configured? What tools does it expose?

**Not configured.** `grep -rn -i "mcpbridge"` over `/Users/jason/.config/opencode/`
returned zero hits. The only `"mcp"` matches in the repo are the planning
references listed in §4 — no wiring.

The bridge **binary itself ships with the installed Xcode** and was probed
read-only:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun mcpbridge --help
```

Result: exit `0`. Output header: `STDIO Bridge for Xcode MCP Tools`,
subcommand `run-agent`, env vars `MCP_XCODE_PID` / `MCP_XCODE_SESSION_ID`,
"Without a subcommand, acts as a STDIO bridge between MCP clients and
Xcode's MCP tool service."

But no tool enumeration was obtainable from this sandbox, so **no tool list
is claimed**:

```sh
# proper MCP handshake: initialize + notifications/initialized + tools/list,
# piped via python3 subprocess with 20 s timeout, DEVELOPER_DIR set
python3 -c "...subprocess.run(['xcrun','mcpbridge'], input=initialize+initialized+tools/list...)"
```

Result (run twice — once without, once with `MCP_XCODE_PID=23833` pointing at
the running Xcode process): return code `1`, **empty stdout and empty stderr**
both times. So no `tools/list` response exists to transcribe.

Honest gap: an `Xcode` process was running (`pgrep` showed PID 23833
`/Applications/Xcode.app/Contents/MacOS/Xcode`), but whether the Lexvane
project is open in it with external-agent access granted is unknown from this
environment, and this sandbox has no MCP-client attachment to query. The
subagent therefore records the MCP path as **binary-present, session-unbridged**,
not as a success.

## 3. Proof the Lexvane project reads via the available path (CLI fallback)

Project read:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -list -project Lexvane.xcodeproj
```

Result: exit `0`. Reported targets `Lexvane`, `LexvaneTests`; configs
`Debug`, `Release`; scheme `Lexvane`. Run from repo root
`/Users/jason/code/lexvane`.

Fallback build (the exact T003 acceptance command):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Lexvane.xcodeproj -scheme Lexvane -destination 'generic/platform=iOS Simulator'
```

Result: exit `0`, final line `** BUILD SUCCEEDED **` (run 2026-10-11 from
`/Users/jason/code/lexvane`; default DerivedData; xcode-select still points at
`/Library/Developer/CommandLineTools`, hence the mandatory `DEVELOPER_DIR`).

## 4. Planning references (not modified)

- `planning/v1/docs/02-architecture-data.md:13` — "OpenCode + OMO 可以作主要
  agent 介面；Xcode MCP / CLI 作實際平台驗證。[S13][S14]"
- `planning/v1/contracts/sources.json` S13 — "Giving external agents access to
  Xcode … Xcode 外部 agent 可用 `xcrun mcpbridge`；要啟用權限並開啟專案。";
  S14 — OpenCode "MCP servers … local stdio MCP 設定 … 不整份覆蓋既有設定。"
- `planning/v1/agent/AGENTS.md:51,56` — "iOS build/test 以 Xcode 結果為準；
  可用 Xcode MCP，CLI 作 fallback." / "保留既有 OpenCode + OMO 配置，新增 MCP
  只 merge 對應欄位。"
- `planning/v1/contracts/tasks.json` T003 — "接現有 OpenCode 的 Xcode MCP …
  保留 OMO/既有設定；列出工具、成功讀專案/build；沒有 MCP 時記錄 CLI fallback。"

## 5. Fallback command to keep (MCP absent)

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Lexvane.xcodeproj -scheme Lexvane -destination 'generic/platform=iOS Simulator'
```

## 6. Post-T003 addendum (2026-10-11, after the check above)

- Per explicit user request, `mcp.xcode` was merged into
  `~/.config/opencode/opencode.jsonc` via wrapper
  `~/.config/opencode/xcode-mcp.sh` (forces
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` because
  `xcode-select -p` still returns `/Library/Developer/CommandLineTools`).
  Pre-existing JetBrains entries preserved.
- User confirmed via screenshot: Xcode Settings > Intelligence > Allow
  External Agents = **Always**, and `Lexvane.xcodeproj` open in Xcode.
- Direct `initialize→tools/list` handshake retested twice after that:
  RC `1`, empty stdout/stderr (with and without `MCP_XCODE_PID`).
  MCP tool path therefore still **unbridged**; CLI fallback above remains
  the verified path.
- Outstanding for MCP use: `sudo xcode-select -s
  /Applications/Xcode.app/Contents/Developer` (optional, needs admin),
  restart the OpenCode session so the new server loads, then re-run the
  `tools/list` handshake.
