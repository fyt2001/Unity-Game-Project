#Requires -Version 5.1
# UTF-8 with BOM, ASCII only. Windows PowerShell 5.1 (powershell.exe; pwsh is not installed).
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\trusted\verify_from_main.ps1 -Target <branch|commit|worktree dir> [-TrustedRef master] [-Unity]
#
# Runs the gate taken from -TrustedRef (default: master) against -Target, so a branch cannot turn itself green by
# editing the gate (poteto step 3). Stages, in order:
#   RUNNER      if this file differs from <TrustedRef>:tools/trusted/verify_from_main.ps1, the trusted copy is run instead.
#   GATE-TAMPER changes on the target since merge-base(TrustedRef, target) that touch a path listed in the TRUSTED
#               tools/trusted/protected_paths.txt => FAIL ("needs human review"). "shrink:" entries (baselines) may only
#               delete lines. Any added line containing "luacheck:" in a .lua file => FAIL (inline lint switches).
#   STATIC      <trusted>\tools\verify.ps1 -Fast -ProjectRoot <target>: trusted luacheck config, lua_layers rules,
#               scan_patterns rules/allowlist/baselines, runtime_no_editor and lua_tests.json, applied to target sources.
#   UNITY       only with -Unity: <trusted>\tools\unity_test.ps1 -Platform EditMode -ProjectPath <target>. Slow: a fresh
#               worktree has no Library folder, so Unity imports the whole project first.
# A branch/commit target is checked out with "git worktree add --detach" next to the repo (lua_tests.json has
# "../tests/..." entries relative to the project root); the trusted ref goes to %TEMP%\gate_main_<ts>.
# Both temporary worktrees are removed at the end (git worktree remove --force + prune) unless -KeepTemp.
# A directory target must be a worktree of this repo; its uncommitted and untracked files count as changes.
# Exit: 0 = PASS (all stages), 1 = FAIL, 2 = setup/usage error.
# Strongest invocation (nothing from the working tree is executed):
#   git show master:tools/trusted/verify_from_main.ps1 | Out-File -Encoding ascii $env:TEMP\vfm.ps1
#   powershell.exe -NoProfile -ExecutionPolicy Bypass -File $env:TEMP\vfm.ps1 -Repo "<repo>" -Target <branch>
param(
    [Parameter(Mandatory = $true)] [string]$Target,
    [string]$TrustedRef = "master",
    [switch]$Unity,
    [string]$Repo = "",
    [string]$OutDir = "",
    [switch]$KeepTemp,
    [string]$TrustedTree = ""   # internal: set by an outer runner that delegated to the trusted copy
)

$ErrorActionPreference = "Continue"
try { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) } catch { }
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$script:log = New-Object System.Collections.ArrayList
$script:created = New-Object System.Collections.ArrayList

function Say([string]$Line, [string]$Color = "Gray") {
    Write-Host $Line -ForegroundColor $Color
    [void]$script:log.Add($Line)
}

function Invoke-Git([string]$Dir, [string[]]$GitArgs) {
    $out = & git -C $Dir -c core.quotepath=true @GitArgs 2>$null
    $script:gitCode = $LASTEXITCODE
    return @($out)
}

function Normalize-Text([string]$Path) {
    $t = [IO.File]::ReadAllText($Path)
    if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
    return ($t -replace "`r`n", "`n").TrimEnd()
}

function Glob-Regex([string]$Glob) {
    $e = [regex]::Escape($Glob.Trim())
    $e = $e -replace '\\\*\\\*', '.*' -replace '\\\*', '[^/]*' -replace '\\\?', '[^/]'
    return '^' + $e + '$'
}

function Unquote([string]$P) {
    if ($P.Length -ge 2 -and $P.StartsWith('"') -and $P.EndsWith('"')) { return $P.Substring(1, $P.Length - 2) }
    return $P
}

function Remove-Worktree([string]$Path) {
    $null = & git -C $script:Repo worktree remove --force $Path 2>&1
    if (Test-Path -LiteralPath $Path) { Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue }
}

function Main {
    # ---- repo + trusted ref -------------------------------------------------------------------------------
    if (-not $script:Repo) { $script:Repo = (& git -C $PSScriptRoot rev-parse --show-toplevel 2>$null) }
    if (-not $script:Repo) { Say "ERROR not inside a git repository; pass -Repo" "Red"; return 2 }
    $script:Repo = (Resolve-Path -LiteralPath $script:Repo).Path
    $mainWt = @(& git -C $script:Repo worktree list --porcelain 2>$null)[0] -replace '^worktree ', ''
    if ($mainWt) { $script:Repo = (Resolve-Path -LiteralPath $mainWt).Path }
    $repo = $script:Repo
    if (-not $script:OutDir) { $script:OutDir = Join-Path $repo ("Logs\AgentRuns\" + $ts + "_trusted_gate") }
    New-Item -ItemType Directory -Force -Path $script:OutDir | Out-Null

    $trustedSha = @(Invoke-Git $repo @("rev-parse", "--verify", "--quiet", ($TrustedRef + "^{commit}")))[0]
    if (-not $trustedSha) { Say ("ERROR trusted ref not found: " + $TrustedRef) "Red"; return 2 }

    if ($TrustedTree) {
        $trusted = (Resolve-Path -LiteralPath $TrustedTree).Path
    } else {
        $trusted = Join-Path $env:TEMP ("gate_main_" + $ts)
        $o = & git -C $repo worktree add --detach $trusted $trustedSha 2>&1
        if ($LASTEXITCODE -ne 0) { Say ("ERROR git worktree add (trusted) failed: " + ($o -join " ")) "Red"; return 2 }
        [void]$script:created.Add($trusted)
    }
    Say ("trusted  ref=" + $TrustedRef + " sha=" + $trustedSha + " tree=" + $trusted)

    # ---- RUNNER: always execute the trusted copy of this script -------------------------------------------
    $trustedRunner = Join-Path $trusted "tools\trusted\verify_from_main.ps1"
    if (-not (Test-Path -LiteralPath $trustedRunner)) {
        Say ("ERROR " + $TrustedRef + " has no tools/trusted/verify_from_main.ps1; commit the runner to the trusted ref first") "Red"
        return 2
    }
    if (-not $TrustedTree) {
        if ((Normalize-Text $PSCommandPath) -ne (Normalize-Text $trustedRunner)) {
            Say ("RUNNER   this copy differs from " + $TrustedRef + "; delegating to the trusted copy") "Yellow"
            $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $trustedRunner, "-Target", $Target,
                "-TrustedRef", $trustedSha, "-Repo", $repo, "-OutDir", $script:OutDir, "-TrustedTree", $trusted)
            if ($Unity) { $a += "-Unity" }
            if ($KeepTemp) { $a += "-KeepTemp" }
            & powershell.exe @a
            $script:delegated = $true
            return $LASTEXITCODE
        }
        Say "RUNNER   PASS (this copy == trusted copy)" "Green"
    }

    # ---- target -------------------------------------------------------------------------------------------
    if (Test-Path -LiteralPath $Target -PathType Container) {
        $mode = "dir"
        $targetDir = (Resolve-Path -LiteralPath $Target).Path
        $cd = @(Invoke-Git $targetDir @("rev-parse", "--git-common-dir"))[0]
        if (-not $cd) { Say ("ERROR target dir is not a git worktree: " + $targetDir) "Red"; return 2 }
        if (-not [IO.Path]::IsPathRooted($cd)) { $cd = Join-Path $targetDir $cd }
        $rcd = @(Invoke-Git $repo @("rev-parse", "--git-common-dir"))[0]
        if (-not [IO.Path]::IsPathRooted($rcd)) { $rcd = Join-Path $repo $rcd }
        if ((Resolve-Path -LiteralPath $cd).Path -ne (Resolve-Path -LiteralPath $rcd).Path) {
            Say ("ERROR target dir belongs to another repository: " + $targetDir) "Red"; return 2
        }
        $targetSha = @(Invoke-Git $targetDir @("rev-parse", "HEAD"))[0]
    } else {
        $mode = "ref"
        $targetSha = @(Invoke-Git $repo @("rev-parse", "--verify", "--quiet", ($Target + "^{commit}")))[0]
        if (-not $targetSha) { Say ("ERROR target is neither a directory nor a commit/branch: " + $Target) "Red"; return 2 }
        $targetDir = Join-Path (Split-Path $repo -Parent) ("_gate_target_" + $ts)
        $o = & git -C $repo worktree add --detach $targetDir $targetSha 2>&1
        if ($LASTEXITCODE -ne 0) { Say ("ERROR git worktree add (target) failed: " + ($o -join " ")) "Red"; return 2 }
        [void]$script:created.Add($targetDir)
    }
    $base = @(Invoke-Git $repo @("merge-base", $trustedSha, $targetSha))[0]
    if (-not $base) { Say "ERROR no merge-base between trusted ref and target" "Red"; return 2 }
    Say ("target   mode=" + $mode + " input=" + $Target + " sha=" + $targetSha + " tree=" + $targetDir)
    Say ("base     merge-base=" + $base)

    # ---- GATE-TAMPER --------------------------------------------------------------------------------------
    Say "== GATE-TAMPER ==" "Cyan"
    $plain = New-Object System.Collections.ArrayList
    $shrink = New-Object System.Collections.ArrayList
    $ppFile = Join-Path $trusted "tools\trusted\protected_paths.txt"
    if (-not (Test-Path -LiteralPath $ppFile)) { Say "ERROR trusted ref has no tools/trusted/protected_paths.txt" "Red"; return 2 }
    foreach ($raw in [IO.File]::ReadAllLines($ppFile)) {
        $l = $raw.Trim()
        if (-not $l -or $l.StartsWith("#")) { continue }
        if ($l -match '^shrink:\s*(.+)$') { [void]$shrink.Add((Glob-Regex $Matches[1])) } else { [void]$plain.Add((Glob-Regex $l)) }
    }

    if ($mode -eq "ref") {
        $nameStatus = Invoke-Git $repo @("diff", "--name-status", "--no-renames", $base, $targetSha)
        $numstat = Invoke-Git $repo @("diff", "--numstat", "--no-renames", $base, $targetSha)
        $luaDiff = Invoke-Git $repo @("diff", "-U0", "--no-renames", $base, $targetSha, "--", "*.lua")
        $untracked = @()
    } else {
        $nameStatus = Invoke-Git $targetDir @("diff", "--name-status", "--no-renames", $base)
        $numstat = Invoke-Git $targetDir @("diff", "--numstat", "--no-renames", $base)
        $luaDiff = Invoke-Git $targetDir @("diff", "-U0", "--no-renames", $base, "--", "*.lua")
        $untracked = Invoke-Git $targetDir @("ls-files", "--others", "--exclude-standard")
    }
    $added = @{}
    foreach ($n in $numstat) { $p = $n -split "`t"; if ($p.Count -ge 3) { $added[(Unquote $p[2])] = $p[0] } }
    $changes = New-Object System.Collections.ArrayList
    foreach ($s in $nameStatus) { $p = $s -split "`t"; if ($p.Count -ge 2) { [void]$changes.Add(@($p[0].Substring(0, 1), (Unquote $p[1]))) } }
    foreach ($u in $untracked) { if ($u) { [void]$changes.Add(@("?", (Unquote $u))) } }
    Say ("changed files vs base: " + $changes.Count)

    $tamper = 0
    foreach ($c in $changes) {
        $st = $c[0]; $path = $c[1]
        $isShrink = $false
        foreach ($r in $shrink) { if ($path -match $r) { $isShrink = $true; break } }
        if ($isShrink) {
            if ($st -eq "M" -and $added.ContainsKey($path) -and $added[$path] -eq "0") {
                Say ("ok       " + $st + " " + $path + "  (shrink-only file: lines removed only)") "Green"
                continue
            }
            Say ("TAMPER   " + $st + " " + $path + "  (shrink-only file: added=" + $added[$path] + "; baselines may only lose lines)") "Red"
            $tamper++
            continue
        }
        foreach ($r in $plain) {
            if ($path -match $r) { Say ("TAMPER   " + $st + " " + $path + "  (protected gate path)") "Red"; $tamper++; break }
        }
    }
    $file = ""
    foreach ($l in $luaDiff) {
        if ($l.StartsWith("+++ ")) { $file = $l.Substring(4) -replace '^b/', ''; continue }
        if ($l.StartsWith("+") -and $l -match '(?i)luacheck\s*:') { Say ("TAMPER   inline lint directive added in " + $file + ": " + $l.Substring(1).Trim()) "Red"; $tamper++ }
    }
    foreach ($u in $untracked) {
        if ($u -notmatch '\.lua"?$') { continue }
        $full = Join-Path $targetDir (Unquote $u)
        if ((Test-Path -LiteralPath $full) -and (Select-String -LiteralPath $full -Pattern '(?i)luacheck\s*:' -Quiet)) {
            Say ("TAMPER   inline lint directive in new untracked file " + $u) "Red"; $tamper++
        }
    }
    if ($tamper -gt 0) { Say ("FAIL GATE-TAMPER " + $tamper + " issue(s): gate files changed on the target - needs human review") "Red" }
    else { Say "PASS GATE-TAMPER" "Green" }

    # ---- STATIC (trusted verify.ps1 -Fast against the target) ---------------------------------------------
    Say "== STATIC ==" "Cyan"
    $trustedVerify = Join-Path $trusted "tools\verify.ps1"
    $staticFail = $true
    if (-not (Test-Path -LiteralPath $trustedVerify)) { Say "FAIL STATIC trusted ref has no tools/verify.ps1" "Red" }
    else {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $trustedVerify -Fast -ProjectRoot $targetDir -OutDir (Join-Path $script:OutDir "static") 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        foreach ($l in $out) { Say ("  " + $l) }
        if ($code -eq 0) { $staticFail = $false; Say "PASS STATIC" "Green" } else { Say ("FAIL STATIC exit=" + $code) "Red" }
    }

    # ---- UNITY (optional) ---------------------------------------------------------------------------------
    $unityFail = $false
    if ($Unity) {
        Say "== UNITY ==" "Cyan"
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $trusted "tools\unity_test.ps1") -Platform EditMode -ProjectPath $targetDir 2>&1 | ForEach-Object { "$_" }
        $code = $LASTEXITCODE
        foreach ($l in $out) { Say ("  " + $l) }
        if ($code -eq 0) { Say "PASS UNITY" "Green" } else { $unityFail = $true; Say ("FAIL UNITY exit=" + $code) "Red" }
    } else {
        Say "SKIP UNITY (pass -Unity to run EditMode tests with the trusted runner)" "DarkGray"
    }

    $fail = ($tamper -gt 0) -or $staticFail -or $unityFail
    if ($fail) { Say ("TRUSTED GATE FAIL  ref=" + $TrustedRef + " target=" + $Target) "Red"; return 1 }
    Say ("TRUSTED GATE PASS  ref=" + $TrustedRef + " target=" + $Target) "Green"
    return 0
}

$script:delegated = $false
$exitCode = 2
try {
    $exitCode = Main
    if ($exitCode -is [array]) { $exitCode = $exitCode[-1] }
} catch {
    Say ("ERROR " + $_.Exception.Message) "Red"
    $exitCode = 2
} finally {
    if (-not $KeepTemp) {
        for ($i = $script:created.Count - 1; $i -ge 0; $i--) { Remove-Worktree $script:created[$i] }
        if ($script:Repo) { $null = & git -C $script:Repo worktree prune 2>&1 }
    } elseif ($script:created.Count -gt 0) {
        Say ("kept temp worktrees: " + ($script:created -join "; ")) "Yellow"
    }
    if ($script:OutDir -and (Test-Path -LiteralPath $script:OutDir) -and -not $script:delegated) {
        [IO.File]::WriteAllLines((Join-Path $script:OutDir "trusted_gate.txt"), [string[]]$script:log.ToArray(), (New-Object Text.UTF8Encoding($false)))
    }
}
exit ([int]$exitCode)
