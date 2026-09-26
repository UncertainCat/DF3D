# Interactive live view: boot DF (hidden desktop, contained), hands-off
# enable the bridge at the title screen, then open the Godot fort loader
# VISIBLY on your desktop and hold DF alive until Godot is closed.
#
# Controls in Godot: RMB orbit, MMB pan, wheel zoom, WASD/QE fly, Shift
# speed, P pauses / O resumes through the command path.
# -Attach owns only Godot; DF is never adopted, stopped or staged.
#
# Containment (Df3dLane.psm1): DF and Godot live in this
# process's job object in owned mode; closing this window ends both.
# Attach mode contains only Godot. Only one lane at a time.
param(
    [string]$DfPath,
    [string]$GodotExe,
    [switch]$CheckInstall,
    [switch]$Attach,
    [switch]$Silent,
    [ValidateSet('project','safe','separate')][string]$RenderThread = 'project',
    [Alias('Profile')][ValidateSet('off','basic','deep')][string]$Profiling = 'off',
    [int]$DfProcessId = 0,
    [int]$Port = 5010,
    [int]$BootTimeoutSec = 420,
    [int]$MaxMinutes = 120
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "AudioTakeover.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'tools\SteamPaths.psm1') -Force
try {
    $DfPath = Resolve-Df3dDfPath -DfPath $DfPath
    $GodotExe = Resolve-Df3dGodotExe -GodotExe $GodotExe
} catch {
    Write-Host "[play] FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}
$projectDir = Join-Path $repo "presentations\godot\project"
$audioGuard = $null
$gProc = $null
$audioSilent = $Silent -or $env:DF3D_AUDIO_SILENT -eq '1'

if (-not (Test-Path -LiteralPath $GodotExe)) { Write-Host "[play] FAIL: Godot not found at $GodotExe" -ForegroundColor Red; exit 1 }
if (-not (Test-Path (Join-Path $projectDir "bin\df3d_godot.dll"))) { Write-Host "[play] FAIL: extension not built (presentations/godot/project/bin/df3d_godot.dll)" -ForegroundColor Red; exit 1 }
Write-Host "[play] Dwarf Fortress: $DfPath"
Write-Host "[play] Godot: $GodotExe"
if ($CheckInstall) {
    foreach ($file in @('dfhooks.dll', 'hack\plugins\df3d.plug.dll', 'hack\dfhack-run.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $DfPath $file) -PathType Leaf)) {
            Write-Host "[play] FAIL: missing $file. Build/install the pinned bridge with tools/build_bridge.ps1." -ForegroundColor Red
            exit 1
        }
    }
    Write-Host '[play] INSTALL_PATHS_PASS: executables, extension and bridge files found. This does not verify versions, DLL loading or a live connection.'
    exit 0
}

try {
    Enter-Df3dLane -DfPath $DfPath -Port $Port -AttachOnly:$Attach
} catch {
    Write-Host "[play] FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

try {
    if ($Attach) {
        $existing = @(Get-Process -Name "Dwarf Fortress" -ErrorAction SilentlyContinue)
        if ($existing.Count -ne 1) { throw "Attach requires exactly one running DF (the mirror is session-wide). Start DFHack-enabled DF first." }
        $dfProc = $existing[0]
        if ($DfProcessId -and $dfProc.Id -ne $DfProcessId) { throw "Requested DF pid $DfProcessId is not the running DF" }
        $expected = [IO.Path]::GetFullPath((Join-Path $DfPath "Dwarf Fortress.exe"))
        if (-not $dfProc.Path -or $dfProc.Path -ne $expected) { throw "DF pid $($dfProc.Id) does not match $expected; pass -DfPath for its install." }
        $status = Invoke-DfhackRaw @("df3d", "status") -TimeoutSec 15
        $message = $status.Output -join "`n"
        if ($status.ExitCode -ne 0 -or $message -notmatch 'mirroring enabled:\s+yes') {
            throw "Cannot read an enabled df3d bridge. In DFHack run 'enable df3d'; check -Port (default 5010) and plugin installation. $message"
        }
        Write-Host "[play] attaching to DF pid $($dfProc.Id); closing this viewer leaves DF running. Pause state preserved."
    } else {
        Set-DfPrefs
        Install-DfMenuStartup -DfPath $DfPath
        $dfProc = Start-Df3d -DfPath $DfPath
        $bootDeadline = (Get-Date).AddSeconds($BootTimeoutSec)
        $bridgeReady = $false
        while ((Get-Date) -lt $bootDeadline) {
            $dfProc.Refresh()
            if ($dfProc.HasExited) { throw "DF exited before its bridge was ready" }
            $status = Invoke-DfhackRaw @("df3d", "status") -TimeoutSec 10
            if ($status.ExitCode -eq 0 -and ($status.Output -join "`n") -match 'mirroring enabled:\s+yes') { $bridgeReady = $true; break }
            Start-Sleep -Milliseconds 500
        }
        if (-not $bridgeReady) { throw "DF bridge did not become ready within $BootTimeoutSec seconds" }
        Write-Host "[play] choose a fort in Godot; closing Godot ends this temporary session without saving"
    }
    # Owned mode already silences DF with temporary lane preferences. Attach
    # uses process sessions, without writing the user's DF preferences.
    if ($Attach) { $audioGuard = Start-DfAudioTakeover -Helper (Join-Path $repo 'build\tools\audio_guard.exe') -DfProcess $dfProc }
    $env:DF3D_DF_PATH = $DfPath
    $env:DF3D_FIXTURE = ""
    # Clear offline diagnostic hooks inherited from a prior screenshot shell.
    Get-ChildItem Env:DF3D_* | Where-Object Name -ne "DF3D_DF_PATH" | Remove-Item
    $env:DF3D_PROFILE = $Profiling
    if ($Profiling -ne 'off') {
        $env:DF3D_PROFILE_OUT = Join-Path $repo ("build/profiles/play-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
        Write-Host "[play] $Profiling profiling enabled; capture on normal close: $env:DF3D_PROFILE_OUT"
    }
    if ($audioSilent) { $env:DF3D_AUDIO_SILENT = '1' }
    $env:DF3D_SCREENSHOT = ""
    $threadArgs = if ($RenderThread -eq 'project') { '' } else { "--render-thread $RenderThread " }
    $gProc = Start-ContainedProcess -Exe $GodotExe -Arguments "${threadArgs}--path `"$projectDir`"" -WorkingDir $projectDir -Visible
    $deadline = (Get-Date).AddMinutes($MaxMinutes)
    while (-not $gProc.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        $gProc.Refresh()
        $dfProc.Refresh()
        if ($dfProc.HasExited) { Write-Host "[play] DF exited (code $($dfProc.ExitCode)); closing Godot"; Stop-Process -Id $gProc.Id -Force -Confirm:$false -ErrorAction SilentlyContinue; break }
        if ($audioGuard) { Assert-DfAudioTakeover $audioGuard }
    }
    if (-not $gProc.HasExited) { Write-Host "[play] time limit reached; closing Godot"; Stop-Process -Id $gProc.Id -Force -Confirm:$false -ErrorAction SilentlyContinue }
    Write-Host "[play] Godot closed"
} catch {
    Write-Host "[play] FAIL: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    if ($gProc -and -not $gProc.HasExited) { Stop-Process -Id $gProc.Id -Force -Confirm:$false -ErrorAction SilentlyContinue }
    try { Stop-DfAudioTakeover $audioGuard }
    finally { Exit-Df3dLane }
}
Write-Host "[play] done"
exit 0
