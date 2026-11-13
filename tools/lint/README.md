# Agent gates and verification

All scripts target **Windows PowerShell 5.1 (`powershell.exe`)**. `pwsh` (PowerShell 7) is not installed on this machine, so do not call it. Run everything from the Unity project root `My project`:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\lint\run_gate.ps1            # static gate
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\lint\run_gate.ps1 -SelfTest  # gate + proves each rule can fail
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\verify.ps1 -Fast             # pure-Lua tests (~2 s)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\verify.ps1 -Full             # + Unity EditMode + Play-mode harness suite
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\unity_test.ps1 -Platform EditMode [-Filter X] [-SelfTest] [-LuaRoot dir]
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\game.ps1 play|script <json>|gm <id> [arg]|click Window/node|shot|log|suite
```

Script conventions: UTF-8 with BOM, ASCII string literals, CRLF. Native tools are launched with stdout and stderr captured, because in 5.1 `2>&1` combined with `$ErrorActionPreference='Stop'` turns stderr text into terminating errors. The Python linters print everything to stdout and do not write `__pycache__`.

## Static gate (`run_gate.ps1`)

| Step | What it checks | Policy |
|---|---|---|
| luacheck | Undefined or accidental Lua globals (`.luacheckrc`) | Zero |
| LUA-LAYER (`lua_layers.py`, `lua_layers.json`) | FW-GAME: `Framework` must not require `Game.*`. DATA-UP: `Game.Save`, `Game.Online` and `Game.Mod` must not require `Game.UI`, `Game.Scene`, `Game.Battle` or `Game.Dungeon`. UI-GM: UI outside `Game.UI.GM` must not require `Game.GM.*`. UI-BATTLEMGR: UI must not call `GetBattleManager()`. CYCLE: package cycles among Battle, Build and Dungeon | FW-GAME is hard and never baselined. The rest use `lua_layers.baseline.txt` |
| SCAN (`scan_patterns.py`, `patterns.json`) | NO-FIND: global scene searches. NO-SWALLOW: empty `catch`. NO-PRINT: Lua `print`. RES-MIX: `Resources.Load` | `allowlist.txt` holds reviewed exceptions. `baseline.txt` holds existing debt |
| RUNTIME-NO-EDITOR | `UnityEditor` used in runtime code outside `#if UNITY_EDITOR` | Hard zero |

How the checks parse code:

- Comments and strings are masked before matching, so commented-out code does not count. Lazy `require` calls inside functions do count.
- Baseline keys are `RULE|file|module-or-normalized-line`, with no line numbers, so moving code around does not create noise.

How the baselines behave:

- Baselines may only shrink. Anything new fails.
- When a baseline entry has been fixed, delete its line. A stale entry is reported but does not fail the gate.
- `--write-baseline` exists only to bootstrap a baseline. Never use it to silence a new hit.

`-SelfTest` writes probes only under `%TEMP%`. It checks three things:

- An unchanged copy of the project passes.
- Each rule fails on a planted violation: a new Framework->Game require, a new Build->Dungeon lazy require (CYCLE), a UI->GM require, a new empty catch, and a new `GameObject.Find`.
- A `Find` that appears only in a comment is ignored.

## Tests (`verify.ps1`, `tools/lua_tests.json`)

`lua_tests.json` is the single list of Lua tests. Each entry has one of these modes:

| Mode | Where it runs | Effect on the verdict |
|---|---|---|
| `fast` | Plain `lua.exe` | Blocking |
| `xlua` | Needs `CS.*`, so it runs inside Unity's LuaEnv through EditMode `LuaSuiteTests` | Blocking in `-Full` |
| `quarantine` | Runs and is reported as QUAR | Never blocks. The entry must give a reason |
| `runtime` | Needs a live game session | Skipped |

Output goes to `Logs\AgentRuns\<timestamp>_verify\` and includes `summary.txt` and one log per check. `Logs/` is ignored by git.

`unity_test.ps1` behavior:

- It refuses to run while the Editor holds `Temp\UnityLockfile` (exit 10), and it never kills the Editor.
- EditMode runs with `-nographics`. PlayMode does not.
- It never passes `-quit` together with `-runTests`.
- It prints `RESULT total= passed= failed= skipped= xml= log=`.
- If no result XML is produced, it exits 11.

Measured Unity / script exit codes on this machine (2026-11-13, Unity 2021.3.9f1c1, com.unity.test-framework 1.1.31):

- UTF (Unity process) **pass**: exit **0**. Measured with `-Filter Game.AgentTests.LuaFieldReaderTests` (2 passed, XML `result=Passed`).
- UTF (Unity process) **fail**: exit **2**. Measured with the contract-rename `-LuaRoot` run (`LuaModulesExposeEveryContractKeyWithTheRightType` failed; XML `result=Failed(Child)`).
- When no Unity license is activated, batchmode exits with **1** and writes no XML. The log shows `No ULF license found` (measured 2026-11-12).
- Intermittent shutdown crash: after the XML is already written, Unity can exit **-1073741819** (`0xC0000005`) with a stack in `UnityEditor::CoreBusinessMetrics::MetricsCache::TrySendPostDataCN`. This was seen on the full EditMode suite (19 passed, 1 skipped, 0 failed) and on `-SelfTest`. It is a Unity editor telemetry crash, not a test failure. `unity_test.ps1` treats XML `failed=0` plus this specific stack as a test pass (prints WARN, exits 0). Any other non-zero Unity exit with a missing or failing XML still fails.

Merge evidence for EditMode:

- NUnit XML: `Logs\AgentRuns\<yyyyMMdd_HHmmss>_unity_EditMode\EditMode.xml` (`total` / `passed` / `failed` / `skipped`). `failed=0` is the pass criterion.
- Unity log next to it: `EditMode.log`.
- The script's last `RESULT platform=... total=... passed=... failed=... skipped=... result=... unity_exit=... xml=... log=...` line, plus the script exit code (0 = pass).
- `verify.ps1 -Full` writes `Logs\AgentRuns\<ts>_verify\summary.txt` and `unity_EditMode.txt`. Harness evidence is `Logs\AgentRuns\<ts>_harness_<name>\result.json`.

## Play-mode harness (`Assets/Editor/AgentHarness`, `tools/game.ps1`, `tools/harness_scripts`)

The harness is a structured replacement for sending free-form C# through `mcp_unity -Code`. Each action is a fixed op in a JSON script: `waitLaunch`, `waitLua`, `assertLua`, `wait`, `click`, `gm`, `joystick`, `screenshot` and `dumpLog`. A script can `include` another script.

Each run does the following:

- It points `Core.Storage` at a sandbox directory, so the real save is never touched.
- It sets a temporary account name.
- It hashes the real save before and after the run.
- It restores the open scenes when it finishes.
- It writes `result.json` (pass, steps, errors, save) and PNG screenshots to `Logs\AgentRuns\<ts>_harness_<name>\`.

Logged errors and exceptions fail the run. So do warnings that contain any string listed in `failOnWarningContains`; smoke uses `[LuaFieldReader]`. Setting `AGENT_HARNESS_INJECT=lua_error` raises a Lua error after launch, which proves the run turns FAIL.

How the run is launched:

| Editor state | What happens |
|---|---|
| Closed | Batchmode `-executeMethod Game.AgentHarnessEditor.AgentHarness.RunScriptBatch`, without `-quit` and without `-nographics` |
| Open | The request is written to `Temp\AgentHarness\inbox`. The Editor polls it every second, and requests older than 120 s are dropped |

## C#<->Lua reads (`Assets/Game/Scripts/Core/LuaFieldReader.cs`)

How `LuaFieldReader.TryGet` and `GetOr` read a field:

- For value types they call `ContainsKey` first, because xLua's `Get` leaks a stack slot when it throws on nil.
- They do not allocate on the hot path.
- The first time a field fails to read, they log one warning that names the key and type.

`LuaContractTests` pins the 22 key reads in `HomeSceneBootstrapper.cs` to a declared contract (owner, key, Lua type). It then checks those types against a live `BattleManager` and spawned enemy. To run the contract against a mutated copy of the Lua tree, set `AGENT_LUA_ROOT` (`unity_test.ps1 -LuaRoot`).

## Rollback

- Backups and SHA256s of every pre-existing file that was touched are in `C:\ProjectsRoot\Unity_1\_backup\20261112_agent_s4_s11\` (`MANIFEST.txt`).
- New files are listed in `NEW_FILES.txt`. To undo them, delete those files and their `.meta`.
