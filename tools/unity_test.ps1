#Requires -Version 5.1
# UTF-8 with BOM. Windows PowerShell 5.1 (powershell.exe; pwsh is not installed).
# Runs Unity Test Framework tests in batchmode and reports with exit codes.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\unity_test.ps1 [-Platform EditMode|PlayMode] [-Filter regex] [-LuaRoot dir] [-SelfTest]
# Exit: 0 = all tests passed (XML failed=0; or a documented CoreBusinessMetrics shutdown crash after that);
#       10 = Editor has the project open (Temp\UnityLockfile locked) - nothing was started;
#       11 = no result XML (compile error or Unity crash before results, see log); 12 = -SelfTest did not fail as expected;
#       2  = tests failed and Unity reported 0, or UTF's own failing exit (measured: 2). See tools\lint\README.md.
# Verdict is taken from the NUnit XML. Do not treat a Unity crash as a pass unless the XML is complete and failed=0
# and the log stack is the known shutdown telemetry crash.
# Never kills a running Editor. Do not run while streaming (batchmode refreshes Library/Temp and uses CPU).
param(
    [ValidateSet("EditMode", "PlayMode")] [string]$Platform = "EditMode",
    [string]$Filter = "",
    [string]$LuaRoot = "",
    # Project to test; empty = parent of tools\ (old behaviour). Used by verify.ps1 -ProjectRoot (trusted mode).
    [string]$ProjectPath = "",
    [switch]$SelfTest
)

$ErrorActionPreference = "Stop"
$Unity = "C:\Program Files\Unity\Hub\Editor\2021.3.9f1c1\Editor\Unity.exe"
if ($ProjectPath) { $Project = (Resolve-Path -LiteralPath $ProjectPath).Path } else { $Project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path }
$Out = Join-Path $Project ("Logs\AgentRuns\" + (Get-Date -Format "yyyyMMdd_HHmmss") + "_unity_" + $Platform)

function Test-EditorOpen([string]$ProjectPath) {
    $lock = Join-Path $ProjectPath "Temp\UnityLockfile"
    if (-not (Test-Path -LiteralPath $lock)) { return $false }
    try {
        $fs = [IO.File]::Open($lock, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        $fs.Close()
        return $false   # stale lockfile left by a crash: Unity itself will take it over
    } catch { return $true }
}

if (Test-EditorOpen $Project) {
    Write-Host "LOCKED Unity Editor has this project open (Temp\UnityLockfile is held). Close the Editor, or use the in-Editor Test Runner. Nothing was started." -ForegroundColor Yellow
    exit 10
}
if (-not (Test-Path -LiteralPath $Unity)) { Write-Host "FAIL Unity not found: $Unity" -ForegroundColor Red; exit 11 }
New-Item -ItemType Directory -Force -Path $Out | Out-Null

$xml = Join-Path $Out ($Platform + ".xml")
$log = Join-Path $Out ($Platform + ".log")
$argList = @("-batchmode", "-projectPath", ('"' + $Project + '"'), "-runTests", "-testPlatform", $Platform,
    "-testResults", ('"' + $xml + '"'), "-logFile", ('"' + $log + '"'))
if ($Platform -eq "EditMode") { $argList = @("-nographics") + $argList }   # PlayMode keeps graphics for rendering
if ($SelfTest) { $Filter = "Game.AgentTests.AgentSelfTest" }
if ($Filter) { $argList += @("-testFilter", ('"' + $Filter + '"')) }

$saved = @{ AGENT_SELFTEST_FAIL = $env:AGENT_SELFTEST_FAIL; AGENT_LUA_ROOT = $env:AGENT_LUA_ROOT }
try {
    if ($SelfTest) { $env:AGENT_SELFTEST_FAIL = "1" }
    if ($LuaRoot) { $env:AGENT_LUA_ROOT = (Resolve-Path $LuaRoot).Path }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $Unity -ArgumentList $argList -Wait -PassThru -NoNewWindow
    $code = $p.ExitCode
} finally {
    $env:AGENT_SELFTEST_FAIL = $saved.AGENT_SELFTEST_FAIL
    $env:AGENT_LUA_ROOT = $saved.AGENT_LUA_ROOT
}

Write-Host ("unity exit=" + $code + " seconds=" + [int]$sw.Elapsed.TotalSeconds)
if (-not (Test-Path -LiteralPath $xml)) {
    Write-Host "FAIL no result XML; first compiler errors from the log:" -ForegroundColor Red
    if (Test-Path -LiteralPath $log) {
        Select-String -LiteralPath $log -Pattern "error CS\d+|Scripts have compiler errors|Aborting batchmode" | Select-Object -First 15 | ForEach-Object { Write-Host ("  " + $_.Line) }
    }
    Write-Host ("RESULT platform=" + $Platform + " xml=missing log=" + $log)
    exit 11
}

[xml]$doc = Get-Content -LiteralPath $xml -Raw -Encoding UTF8
$run = $doc.SelectSingleNode("/test-run")
Write-Host ("RESULT platform=" + $Platform + " total=" + $run.total + " passed=" + $run.passed + " failed=" + $run.failed +
    " skipped=" + $run.skipped + " result=" + $run.result + " unity_exit=" + $code + " xml=" + $xml + " log=" + $log)
foreach ($tc in $doc.SelectNodes("//test-case[@result='Failed']")) {
    $msg = $tc.failure.message.InnerText
    if (-not $msg) { $msg = [string]$tc.failure.message }
    Write-Host ("  FAILED " + $tc.fullname + " :: " + ($msg -replace "\s+", " ").Trim()) -ForegroundColor Red
}
foreach ($tc in $doc.SelectNodes("//test-case[@result='Skipped']")) {
    Write-Host ("  SKIPPED " + $tc.fullname + " :: " + (([string]$tc.reason.message.InnerText) -replace "\s+", " ").Trim()) -ForegroundColor DarkGray
}

function Test-ShutdownTelemetryCrash([string]$LogPath, [int]$UnityCode) {
    # Observed 2026-11-13: Unity 2021.3.9f1c1 can access-violate in CoreBusinessMetrics
    # on shutdown after results are already written. Signed exit is -1073741819 (0xC0000005).
    if ($UnityCode -ne -1073741819) { return $false }
    if (-not (Test-Path -LiteralPath $LogPath)) { return $false }
    $stack = Select-String -LiteralPath $LogPath -Pattern "OUTPUTTING STACK TRACE" | Select-Object -First 1
    $metrics = Select-String -LiteralPath $LogPath -Pattern "CoreBusinessMetrics::MetricsCache::TrySendPostData" | Select-Object -First 1
    return [bool]$stack -and [bool]$metrics
}

if ($SelfTest) {
    if ($code -ne 0 -and [int]$run.failed -ge 1) { Write-Host "PASS self-test: deliberate failure produced unity exit $code" -ForegroundColor Green; exit 0 }
    Write-Host "FAIL self-test: expected a failing run, got exit $code failed=$($run.failed)" -ForegroundColor Red
    exit 12
}

$failed = [int]$run.failed
if ($failed -gt 0) {
    if ($code -eq 0) { exit 2 }   # never report green with failures, whatever Unity returned
    exit $code
}
if ($code -eq 0) { exit 0 }
if (Test-ShutdownTelemetryCrash $log $code) {
    Write-Host ("WARN unity exit=" + $code + " is a shutdown crash in CoreBusinessMetrics after XML was written (failed=0). Script exits 0. log=" + $log) -ForegroundColor Yellow
    exit 0
}
exit $code
