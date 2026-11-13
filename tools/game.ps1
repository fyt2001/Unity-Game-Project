#Requires -Version 5.1
# UTF-8 with BOM. Windows PowerShell 5.1 (powershell.exe; pwsh is not installed).
# Structured game driver (AgentHarness). No free-form C#: every action is a fixed harness op in a JSON script.
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\game.ps1 script tools\harness_scripts\smoke_login_home.json
#   ... game.ps1 play                      # launch + login + Home (= smoke_login_home)
#   ... game.ps1 gm currency.add_gold 500  # after login, run one GM command by id
#   ... game.ps1 click LoginPanel/m_LoginBtn   # after launch, click a node inside a UI window
#   ... game.ps1 shot                      # after login, screenshot Home
#   ... game.ps1 log                       # print the newest run's result.json
#   ... game.ps1 suite                     # every script in tools\harness_scripts\suite.json
# Editor closed -> batchmode -executeMethod Game.AgentHarnessEditor.AgentHarness.RunScriptBatch (no -quit, no -nographics).
# Editor open   -> request file in Temp\AgentHarness\inbox (the Editor polls it once per second); never kills the Editor.
# Exit: 0 pass, 1 fail, 3 harness error, 10 Editor busy/unreachable, 11 Unity failed to start the run.
# Env: AGENT_HARNESS_INJECT=lua_error makes the harness raise a Lua error right after launch (self-test).
param(
    [Parameter(Position = 0)] [ValidateSet("script", "play", "gm", "click", "shot", "log", "suite")] [string]$Command = "play",
    [Parameter(Position = 1)] [string]$Target = "",
    [Parameter(Position = 2)] [string]$Value = "",
    [int]$TimeoutSec = 900
)

$ErrorActionPreference = "Stop"
$Unity = "C:\Program Files\Unity\Hub\Editor\2021.3.9f1c1\Editor\Unity.exe"
$Project = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$Scripts = Join-Path $PSScriptRoot "harness_scripts"
$Runs = Join-Path $Project "Logs\AgentRuns"
$Utf8 = New-Object Text.UTF8Encoding($false)

function Test-EditorOpen {
    $lock = Join-Path $Project "Temp\UnityLockfile"
    if (-not (Test-Path -LiteralPath $lock)) { return $false }
    try { $fs = [IO.File]::Open($lock, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None); $fs.Close(); return $false }
    catch { return $true }
}

function New-AdhocScript([string]$Name, [string]$Include, [object[]]$Steps) {
    $dir = Join-Path $Runs "_adhoc"
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    Copy-Item -Force -Path (Join-Path $Scripts "*.json") -Destination $dir
    $obj = [ordered]@{ name = $Name; include = $Include; timeoutSec = 300; steps = $Steps }
    $path = Join-Path $dir ($Name + ".json")
    [IO.File]::WriteAllText($path, ($obj | ConvertTo-Json -Depth 6), $Utf8)
    return $path
}

function Show-Result([string]$OutDir) {
    $rf = Join-Path $OutDir "result.json"
    if (-not (Test-Path -LiteralPath $rf)) { Write-Host "FAIL no result.json in $OutDir" -ForegroundColor Red; return $false }
    $r = Get-Content -LiteralPath $rf -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($s in @($r.steps)) {
        if ($null -eq $s) { continue }
        $st = $(if ($s.pass) { "ok  " } else { "FAIL" })
        Write-Host ("  {0} [{1}] {2} {3}" -f $st, $s.index, $s.label, $(if ($s.detail) { "- " + $s.detail } else { "" }))
    }
    foreach ($e in @($r.errors)) { if ($e) { Write-Host ("  error: " + $e) -ForegroundColor Red } }
    if ($r.save) { Write-Host ("  save unchanged=" + $r.save.unchanged + " sandbox=" + $r.save.sandbox + " redirected=" + $r.save.redirectedCalls) }
    Write-Host ("  screenshots: " + (@($r.screenshots) -join ", "))
    $status = $(if ($r.pass) { "PASS" } else { "FAIL" })
    Write-Host ("{0} {1} steps={2} errors={3} {4}" -f $status, $r.script, @($r.steps).Count, @($r.errors).Count, $rf) -ForegroundColor $(if ($r.pass) { "Green" } else { "Red" })
    return [bool]$r.pass
}

function Invoke-Script([string]$ScriptPath) {
    $full = (Resolve-Path $ScriptPath).Path
    $name = [IO.Path]::GetFileNameWithoutExtension($full)
    $out = Join-Path $Runs ((Get-Date -Format "yyyyMMdd_HHmmss") + "_harness_" + $name)
    New-Item -ItemType Directory -Force -Path $out | Out-Null
    if (Test-EditorOpen) {
        $inbox = Join-Path $Project "Temp\AgentHarness\inbox"
        New-Item -ItemType Directory -Force -Path $inbox | Out-Null
        $req = [ordered]@{ id = [guid]::NewGuid().ToString("N"); script = $full; outDir = $out }
        [IO.File]::WriteAllText((Join-Path $inbox ($req.id + ".json")), ($req | ConvertTo-Json), $Utf8)
        Write-Host "Editor is open: queued $name in Temp\AgentHarness\inbox (Editor must not be compiling or in Play)."
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
            $rf = Join-Path $out "result.json"
            if ((Test-Path -LiteralPath $rf) -and ((Get-Content -LiteralPath $rf -Raw) -match '"status"\s*:\s*"done"')) {
                if (Show-Result $out) { return 0 } else { return 1 }
            }
        }
        Remove-Item -LiteralPath (Join-Path $inbox ($req.id + ".json")) -ErrorAction SilentlyContinue   # withdraw: the Editor also drops requests older than 120 s
        Write-Host "TIMEOUT waiting for the open Editor to run $name (is it focused/compiling/in Play?)" -ForegroundColor Yellow
        return 10
    }
    $log = Join-Path $out "unity.log"
    $argList = @("-batchmode", "-projectPath", ('"' + $Project + '"'), "-executeMethod", "Game.AgentHarnessEditor.AgentHarness.RunScriptBatch",
        "-agentScript", ('"' + $full + '"'), "-agentOut", ('"' + $out + '"'), "-logFile", ('"' + $log + '"'))
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = Start-Process -FilePath $Unity -ArgumentList $argList -PassThru -NoNewWindow
    $null = $p.Handle   # PS 5.1: cache the handle so ExitCode is available after WaitForExit
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        Write-Host "TIMEOUT batch run exceeded $TimeoutSec s; stopping only the batch Unity process this script started (pid $($p.Id))" -ForegroundColor Yellow
        Stop-Process -Id $p.Id -Force
        return 3
    }
    Write-Host ("unity exit=" + $p.ExitCode + " seconds=" + [int]$sw.Elapsed.TotalSeconds + " log=" + $log)
    $ok = Show-Result $out
    if ($p.ExitCode -eq 3) { return 3 }
    if (-not (Test-Path -LiteralPath (Join-Path $out "result.json"))) { return 11 }
    if ($ok) { return 0 } else { return 1 }
}

switch ($Command) {
    "script" { exit (Invoke-Script $Target) }
    "play" { exit (Invoke-Script (Join-Path $Scripts "smoke_login_home.json")) }
    "gm" {
        $step = [ordered]@{ op = "gm"; label = ("GM " + $Target); gm = $Target }
        if ($Value) { $step.arg = $Value }
        exit (Invoke-Script (New-AdhocScript ("adhoc_gm") "smoke_login_home.json" @($step, [ordered]@{ op = "screenshot"; name = "after_gm" })))
    }
    "click" {
        $parts = $Target.Split("/", 2)
        $step = [ordered]@{ op = "click"; label = ("click " + $Target); window = $parts[0] }
        if ($parts.Count -gt 1) { $step.node = $parts[1] }
        $pre = [ordered]@{ op = "waitLua"; label = ("window " + $parts[0] + " open"); expr = ("require('Game.GameMain').GetUIManager():IsOpen('" + $parts[0] + "')"); timeoutSec = 60 }
        $launch = [ordered]@{ op = "waitLaunch" }
        $tmp = New-AdhocScript "adhoc_click" "" @($launch, $pre, $step, [ordered]@{ op = "screenshot"; name = "after_click" })
        exit (Invoke-Script $tmp)
    }
    "shot" { exit (Invoke-Script (New-AdhocScript "adhoc_shot" "smoke_login_home.json" @([ordered]@{ op = "screenshot"; name = "shot" }))) }
    "log" {
        $last = Get-ChildItem -LiteralPath $Runs -Directory -Filter "*_harness_*" -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last 1
        if (-not $last) { Write-Host "no harness runs under $Runs"; exit 1 }
        if (Show-Result $last.FullName) { exit 0 } else { exit 1 }
    }
    "suite" {
        $suite = Get-Content -LiteralPath (Join-Path $Scripts "suite.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        $fail = 0
        foreach ($s in $suite.scripts) {
            Write-Host ("== " + $s.path + " (" + $s.mode + ")")
            $code = Invoke-Script (Join-Path $Scripts $s.path)
            $tag = $(if ($code -eq 0) { "PASS" } elseif ($s.mode -eq "quarantine") { "QUAR" } else { "FAIL" })
            Write-Host ("{0} harness:{1} exit={2}" -f $tag, $s.path, $code)
            if ($tag -eq "FAIL") { $fail++ }
            if ($code -eq 10) { break }
        }
        if ($fail -gt 0) { exit 1 } else { exit 0 }
    }
}
