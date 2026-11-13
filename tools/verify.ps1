#Requires -Version 5.1
# UTF-8 with BOM. Windows PowerShell 5.1: use powershell.exe (pwsh is NOT installed on this machine).
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\verify.ps1 -Fast
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\verify.ps1 -Full
# -Fast : luacheck (L1) -> lua_layers (L2) -> scan_patterns (L3/L4) -> runtime_no_editor (L5) -> Lua tests (system lua).
#         No Unity needed. System lua is 5.5 (XLua is 5.3), so Lua results here are a quick signal only;
#         the authoritative run is EditMode LuaSuiteTests inside XLua.
# -Full : -Fast, then tools\unity_test.ps1 EditMode, then the PlayMode stage = tools\game.ps1 suite (AgentHarness
#         scripts F1-F3, F6-F8 in real Play mode). Needs the Editor CLOSED; exit 10 from unity_test = Editor lock.
# Output: one line per check:  PASS|FAIL|SKIP|QUAR <check> <issues> <result file>
# Exit code: 0 = every blocking check passed, 1 = at least one FAIL.
param(
    [switch]$Fast,
    [switch]$Full,
    [string]$Filter = "",
    # Trusted mode (tools\trusted\verify_from_main.ps1): run THIS copy's rules, .luacheckrc and baselines
    # against another checkout. Empty = old behaviour (project = parent of tools\).
    [string]$ProjectRoot = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
if (-not $Fast -and -not $Full) { $Fast = $true }
$ToolsRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ($ProjectRoot) { $ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path } else { $ProjectRoot = $ToolsRoot }
$TrustedMode = ($ProjectRoot -ne $ToolsRoot)
Set-Location -LiteralPath $ProjectRoot
$stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if (-not $OutDir) { $OutDir = Join-Path $ProjectRoot ("Logs\AgentRuns\" + $stamp + "_verify") }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:failures = 0
$script:rows = New-Object System.Collections.ArrayList
$sw = [Diagnostics.Stopwatch]::StartNew()

function Quote-Arg([string]$s) {
    if ($s -eq "") { return '""' }
    if ($s -notmatch '[\s"]') { return $s }
    $e = $s -replace '(\\*)"', '$1$1\"'
    $e = $e -replace '(\\+)$', '$1$1'
    return '"' + $e + '"'
}

# Run a native tool without PowerShell stderr wrapping; returns exit code, writes stdout+stderr to $OutFile.
# .bat/.cmd cannot be started with UseShellExecute=false; cmd /c call keeps the wrapper exit code
# (GitHub Actions + LuaRocks installs luacheck as a .bat).
function Invoke-Tool([string]$Exe, [string[]]$ArgList, [string]$OutFile, [hashtable]$Env = @{}) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $argStr = (($ArgList | ForEach-Object { Quote-Arg $_ }) -join " ")
    if ($Exe -match '\.(bat|cmd)$') {
        $psi.FileName = $env:ComSpec
        $psi.Arguments = "/c call " + (Quote-Arg $Exe) + $(if ($argStr) { " " + $argStr } else { "" })
    } else {
        $psi.FileName = $Exe
        $psi.Arguments = $argStr
    }
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
    $psi.WorkingDirectory = $ProjectRoot
    $psi.EnvironmentVariables["PYTHONIOENCODING"] = "utf-8"
    foreach ($k in $Env.Keys) { $psi.EnvironmentVariables[$k] = [string]$Env[$k] }
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    [IO.File]::WriteAllText($OutFile, $o.Result + $e.Result, (New-Object Text.UTF8Encoding($false)))
    return $p.ExitCode
}

function Rel([string]$Path) {
    if ($Path.StartsWith($ProjectRoot + "\", [StringComparison]::OrdinalIgnoreCase)) { return $Path.Substring($ProjectRoot.Length + 1) }
    return $Path
}

function Report([string]$Status, [string]$Check, [string]$Count, [string]$File) {
    $line = "{0} {1} {2} {3}" -f $Status, $Check, $Count, $File
    $color = @{ PASS = "Green"; FAIL = "Red"; SKIP = "DarkGray"; QUAR = "Yellow" }[$Status]
    Write-Host $line -ForegroundColor $color
    [void]$script:rows.Add($line)
    if ($Status -eq "FAIL") { $script:failures++ }
}

function Count-Match([string]$File, [string]$Pattern) {
    if (-not (Test-Path -LiteralPath $File)) { return 0 }
    return @(Select-String -LiteralPath $File -Pattern $Pattern -Encoding UTF8).Count
}

function First-Match([string]$File, [string]$Pattern, [int]$Group) {
    $m = Select-String -LiteralPath $File -Pattern $Pattern -Encoding UTF8 | Select-Object -Last 1
    if ($m) { return $m.Matches[0].Groups[$Group].Value }
    return "?"
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction SilentlyContinue }
$luacheck = Get-Command luacheck -ErrorAction SilentlyContinue
$lua = Get-Command lua -ErrorAction SilentlyContinue
$lint = Join-Path $PSScriptRoot "lint"

# L1 luacheck
$f = Join-Path $OutDir "luacheck.txt"
if (-not $luacheck) { Report "FAIL" "L1-luacheck" "tool-missing" "-" }
else {
    $lcArgs = @("Assets/Game/LuaScripts", "--no-cache", "--codes", "--formatter", "plain")
    # Trusted mode: the checked tree's own .luacheckrc is ignored; files[] paths resolve against the cwd (= checked tree).
    if ($TrustedMode) { $lcArgs += @("--config", (Join-Path $ToolsRoot ".luacheckrc")) }
    $code = Invoke-Tool $luacheck.Source $lcArgs $f
    $n = Count-Match $f '\(\w\d+\)'
    Report ($(if ($code -eq 0) { "PASS" } else { "FAIL" })) "L1-luacheck" $n (Rel $f)
    if ($code -ne 0 -and (Test-Path -LiteralPath $f)) {
        $txt = [IO.File]::ReadAllText($f)
        if ($txt.Length -eq 0) { Write-Host ("L1-luacheck produced no output (exit=" + $code + ")") }
        else { Write-Host $txt.TrimEnd() }
    }
}

if (-not $python) { Report "FAIL" "python" "tool-missing" "-" }
else {
    # L2 lua_layers
    $f = Join-Path $OutDir "lua_layers.txt"
    $code = Invoke-Tool $python.Source @((Join-Path $lint "lua_layers.py"), $ProjectRoot) $f
    $hard = First-Match $f 'hard=(\d+)' 1; $new = First-Match $f 'new=(\d+)' 1
    Report ($(if ($code -eq 0) { "PASS" } else { "FAIL" })) "L2-lua_layers" ("new=" + $new + ",hard=" + $hard) (Rel $f)

    # L3/L4 scan_patterns
    $f = Join-Path $OutDir "scan_patterns.txt"
    $j = Join-Path $OutDir "scan_patterns.json"
    $code = Invoke-Tool $python.Source @((Join-Path $lint "scan_patterns.py"), $ProjectRoot, "--json", $j) $f
    $new = First-Match $f '\] (?:PASS|FAIL)\s+files=\d+ hits=\d+ new=(\d+)' 1
    Report ($(if ($code -eq 0) { "PASS" } else { "FAIL" })) "L3L4-scan_patterns" ("new=" + $new) (Rel $j)

    # L5 runtime_no_editor
    $f = Join-Path $OutDir "runtime_no_editor.txt"
    $code = Invoke-Tool $python.Source @((Join-Path $lint "runtime_no_editor.py"), $ProjectRoot) $f
    Report ($(if ($code -eq 0) { "PASS" } else { "FAIL" })) "L5-runtime_no_editor" $(if ($code -eq 0) { "0" } else { "see-file" }) (Rel $f)
}

# Lua tests (system lua: quick signal; XLua run is EditMode LuaSuiteTests)
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot "lua_tests.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$rootFwd = $ProjectRoot.Replace("\", "/")
foreach ($t in $manifest.tests) {
    $name = [IO.Path]::GetFileNameWithoutExtension($t.path)
    if ($Filter -and ($name -notmatch $Filter)) { continue }
    $testPath = [IO.Path]::GetFullPath((Join-Path $ProjectRoot $t.path))
    $f = Join-Path $OutDir ("lua_" + $name + ".txt")
    if (-not (Test-Path -LiteralPath $testPath)) { Report "FAIL" ("lua:" + $name) "missing" $t.path; continue }
    if ($t.mode -eq "xlua" -or $t.mode -eq "runtime") {
        Report "SKIP" ("lua:" + $name) $t.mode ("(" + $t.reason + ")")
        continue
    }
    if (-not $lua) { Report "FAIL" ("lua:" + $name) "lua-missing" "-"; continue }
    $code = Invoke-Tool $lua.Source @("-e", ("ROOT=[[" + $rootFwd + "]]"), $testPath, $rootFwd) $f @{ LUA_PATH = ($rootFwd + "/Assets/Game/LuaScripts/?.lua;;") }
    if ($t.mode -eq "quarantine") {
        Report "QUAR" ("lua:" + $name) ("exit=" + $code) (Rel $f)
        continue
    }
    Report ($(if ($code -eq 0) { "PASS" } else { "FAIL" })) ("lua:" + $name) ("exit=" + $code) (Rel $f)
}

$fastMs = $sw.ElapsedMilliseconds
Write-Host ("fast stage: " + $fastMs + " ms")

if ($Full) {
    $f = Join-Path $OutDir "unity_EditMode.txt"
    $code = Invoke-Tool "powershell.exe" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "unity_test.ps1"), "-Platform", "EditMode", "-ProjectPath", $ProjectRoot) $f
    Report ($(if ($code -eq 0) { "PASS" } else { "FAIL" })) "unity:EditMode" ("exit=" + $code) (Rel $f)
    $summary = First-Match $f '^RESULT (.*)$' 1
    if ($summary -ne "?") { Write-Host ("    " + $summary) }
    if ($TrustedMode) {
        Report "SKIP" "unity:PlayMode-harness-suite" "trusted-mode" "(game.ps1 drives the open Editor of the main project only)"
    } elseif ($code -ne 10) {
        # PlayMode stage = AgentHarness scripts in real Play mode (UTF PlayMode tests cannot see Assembly-CSharp before asmdef/S12).
        $f = Join-Path $OutDir "harness_suite.txt"
        $code = Invoke-Tool "powershell.exe" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $PSScriptRoot "game.ps1"), "suite") $f
        Report ($(if ($code -eq 0) { "PASS" } else { "FAIL" })) "unity:PlayMode-harness-suite" ("exit=" + $code) (Rel $f)
        Select-String -LiteralPath $f -Pattern '^(PASS|FAIL|QUAR) harness:' -Encoding UTF8 | ForEach-Object { Write-Host ("    " + $_.Line) }
    }
}

$summaryFile = Join-Path $OutDir "summary.txt"
$script:rows.Add(("total_ms=" + $sw.ElapsedMilliseconds + " failures=" + $script:failures)) | Out-Null
[IO.File]::WriteAllLines($summaryFile, [string[]]$script:rows.ToArray(), (New-Object Text.UTF8Encoding($false)))
if ($script:failures -gt 0) {
    Write-Host ("VERIFY FAIL  " + $script:failures + " check(s)  " + (Rel $summaryFile)) -ForegroundColor Red
    exit 1
}
Write-Host ("VERIFY PASS  " + (Rel $summaryFile)) -ForegroundColor Green
exit 0
