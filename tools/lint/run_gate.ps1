#Requires -Version 5.1
# UTF-8 with BOM. Windows PowerShell 5.1 (powershell.exe, NOT pwsh). Run from anywhere:
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\lint\run_gate.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\lint\run_gate.ps1 -SelfTest
# Static gate: luacheck (L1), LUA-LAYER (L2), scan_patterns (L3/L4 + NO-PRINT/RES-MIX), RUNTIME-NO-EDITOR (L5).
# -SelfTest writes probes only under $env:TEMP and proves each check can fail.
param(
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location -LiteralPath $ProjectRoot
$env:PYTHONIOENCODING = "utf-8"

function Write-Step([string]$Name, [int]$Code) {
    if ($Code -eq 0) { Write-Host "PASS  $Name" -ForegroundColor Green }
    else { Write-Host "FAIL  $Name  exit=$Code" -ForegroundColor Red }
}

function Expect([string]$Name, [bool]$Ok) {
    if ($Ok) { Write-Host "PASS  self-test $Name" -ForegroundColor Green; return 0 }
    Write-Host "FAIL  self-test $Name" -ForegroundColor Red; return 1
}

# Run a python lint script, echo its output, return @{ Code; Text }.
function Invoke-Lint([string]$Script, [string[]]$ScriptArgs) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $lines = & $script:python.Source (Join-Path $PSScriptRoot $Script) @ScriptArgs 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $prev }
    $text = ($lines -join [Environment]::NewLine)
    if ($text) { Write-Host $text }
    return @{ Code = $code; Text = $text }
}

$failures = 0

$luacheck = Get-Command luacheck -ErrorAction SilentlyContinue
if (-not $luacheck) {
    Write-Host "FAIL  luacheck not found on PATH" -ForegroundColor Red
    $failures++
} else {
    & luacheck "Assets/Game/LuaScripts" --no-cache --codes
    $code = $LASTEXITCODE
    Write-Step "luacheck" $code
    if ($code -ne 0) { $failures++ }
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $python) {
    Write-Host "FAIL  python/python3 not found on PATH" -ForegroundColor Red
    $failures++
} else {
    $r = Invoke-Lint "lua_layers.py" @($ProjectRoot)
    Write-Step "LUA-LAYER (FW-GAME hard, DATA-UP/UI-GM/CYCLE/UI-BATTLEMGR baseline)" $r.Code
    if ($r.Code -ne 0) { $failures++ }

    $r = Invoke-Lint "scan_patterns.py" @($ProjectRoot)
    Write-Step "SCAN (NO-FIND/NO-SWALLOW/NO-PRINT/RES-MIX baseline)" $r.Code
    if ($r.Code -ne 0) { $failures++ }

    $r = Invoke-Lint "runtime_no_editor.py" @($ProjectRoot)
    Write-Step "RUNTIME-NO-EDITOR (hard zero-lock)" $r.Code
    if ($r.Code -ne 0) { $failures++ }
}

if ($SelfTest) {
    if (-not $python) {
        Write-Host "FAIL  self-test needs python" -ForegroundColor Red
        $failures++
    } else {
        $nl = [Environment]::NewLine
        $tmp = Join-Path $env:TEMP ("unity_gate_selftest_" + [guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try {
            # --- minimal tree: hard locks ---
            $fw = Join-Path $tmp "Assets\Game\LuaScripts\Framework\Core"
            $scripts = Join-Path $tmp "Assets\Game\Scripts\Core"
            New-Item -ItemType Directory -Path $fw, $scripts -Force | Out-Null

            $badFw = Join-Path $fw "BadRequire.lua"
            Set-Content -LiteralPath $badFw -Value "local Save = require 'Game.Save.SaveData'" -Encoding ASCII
            $r = Invoke-Lint "lua_layers.py" @($tmp)
            $failures += Expect "LUA-LAYER catches Framework->Game" ($r.Code -ne 0)

            $badCs = Join-Path $scripts "BadEditor.cs"
            Set-Content -LiteralPath $badCs -Value ("using UnityEditor;" + $nl + "public class BadEditor {}" + $nl) -Encoding ASCII
            $r = Invoke-Lint "runtime_no_editor.py" @($tmp)
            $failures += Expect "RUNTIME-NO-EDITOR catches bare UnityEditor" ($r.Code -ne 0)

            $okCs = Join-Path $scripts "OkEditor.cs"
            $okBody = '#if UNITY_EDITOR' + $nl + 'using UnityEditor;' + $nl + '#endif' + $nl + 'public class OkEditor {}' + $nl
            Set-Content -LiteralPath $okCs -Value $okBody -Encoding ASCII
            Remove-Item -LiteralPath $badCs
            $r = Invoke-Lint "runtime_no_editor.py" @($tmp)
            $failures += Expect "RUNTIME-NO-EDITOR allows #if UNITY_EDITOR" ($r.Code -eq 0)

            if ($luacheck) {
                $probeDir = Join-Path $tmp "luacheck_probe"
                New-Item -ItemType Directory -Path $probeDir | Out-Null
                $probe = Join-Path $probeDir "accidental_global.lua"
                $probeBody = "function oops()" + $nl + "    definitelyNotAGlobal = 1" + $nl + "end" + $nl
                Set-Content -LiteralPath $probe -Value $probeBody -Encoding ASCII
                & luacheck $probe --no-cache --codes --std lua53 | Out-Null
                $failures += Expect "luacheck catches accidental global" ($LASTEXITCODE -ne 0)
            }

            # --- full copy: baseline behaviour ---
            $copy = Join-Path $tmp "copy"
            New-Item -ItemType Directory -Path (Join-Path $copy "Assets\Game") -Force | Out-Null
            Copy-Item -Recurse -LiteralPath (Join-Path $ProjectRoot "Assets\Game\LuaScripts") -Destination (Join-Path $copy "Assets\Game\LuaScripts")
            Copy-Item -Recurse -LiteralPath (Join-Path $ProjectRoot "Assets\Game\Scripts") -Destination (Join-Path $copy "Assets\Game\Scripts")
            $lua = Join-Path $copy "Assets\Game\LuaScripts"

            $r = Invoke-Lint "lua_layers.py" @($copy)
            $failures += Expect "LUA-LAYER unchanged copy passes (baseline edges not reported)" ($r.Code -eq 0)

            $fwFile = Join-Path $lua "Framework\Core\Class.lua"
            $orig = [IO.File]::ReadAllBytes($fwFile)
            Add-Content -LiteralPath $fwFile -Value ($nl + 'local SaveData = require "Game.Save.SaveData"') -Encoding ASCII
            $r = Invoke-Lint "lua_layers.py" @($copy)
            $failures += Expect "LUA-LAYER FW-GAME fails with fix hint" (($r.Code -eq 1) -and ($r.Text -match "LUA-LAYER/FW-GAME"))
            [IO.File]::WriteAllBytes($fwFile, $orig)

            $bc = Join-Path $lua "Game\Build\BuildConfig.lua"
            $orig = [IO.File]::ReadAllBytes($bc)
            Add-Content -LiteralPath $bc -Value ($nl + "local function lazyProbe()" + $nl + "`treturn require(""Game.Dungeon.DungeonManager"")" + $nl + "end") -Encoding ASCII
            $r = Invoke-Lint "lua_layers.py" @($copy)
            $failures += Expect "LUA-LAYER new cycle edge Build->Dungeon (lazy require) fails" (($r.Code -eq 1) -and ($r.Text -match "LUA-LAYER/CYCLE"))
            [IO.File]::WriteAllBytes($bc, $orig)

            $lv = Join-Path $lua "Game\UI\Shop\UIShopView.lua"
            $orig = [IO.File]::ReadAllBytes($lv)
            Add-Content -LiteralPath $lv -Value ($nl + 'local GMLogProbe = require "Game.GM.GMLog"') -Encoding ASCII
            $r = Invoke-Lint "lua_layers.py" @($copy)
            $failures += Expect "LUA-LAYER UI-GM outside Game.UI.GM fails" (($r.Code -eq 1) -and ($r.Text -match "LUA-LAYER/UI-GM"))
            [IO.File]::WriteAllBytes($lv, $orig)

            $r = Invoke-Lint "scan_patterns.py" @($copy)
            $failures += Expect "SCAN unchanged copy passes" ($r.Code -eq 0)

            $sw = Join-Path $copy "Assets\Game\Scripts\Core\SelfTestSwallow.cs"
            $swBody = "public class SelfTestSwallow {" + $nl + "  void F() {" + $nl + "    try { G(); }" + $nl + "    catch (System.Exception)" + $nl + "    {" + $nl + "      // ignored" + $nl + "    }" + $nl + "  }" + $nl + "  void G() {}" + $nl + "}" + $nl
            Set-Content -LiteralPath $sw -Value $swBody -Encoding ASCII
            $r = Invoke-Lint "scan_patterns.py" @($copy)
            $failures += Expect "SCAN new empty catch fails (NO-SWALLOW)" (($r.Code -eq 1) -and ($r.Text -match "\[NO-SWALLOW\]"))
            Remove-Item -LiteralPath $sw

            $fd = Join-Path $lua "Game\UI\Home\SelfTestFind.lua"
            Set-Content -LiteralPath $fd -Value ("local go = CS.UnityEngine.GameObject.Find(""Probe"")" + $nl + "-- FindObjectOfType in a comment must not count" + $nl) -Encoding ASCII
            $r = Invoke-Lint "scan_patterns.py" @($copy)
            $failures += Expect "SCAN new Find fails (NO-FIND, comment ignored)" (($r.Code -eq 1) -and ($r.Text -match "\[NO-FIND\]") -and ($r.Text -match "new=1 "))
            Remove-Item -LiteralPath $fd
        } finally {
            Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

if ($failures -gt 0) {
    Write-Host ("GATE FAIL  (" + $failures + " item(s))") -ForegroundColor Red
    exit 1
}
Write-Host "GATE PASS" -ForegroundColor Green
exit 0
