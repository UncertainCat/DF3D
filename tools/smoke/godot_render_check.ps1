# Tier-4 render check for the Godot presentation: boots DF (hidden desktop),
# hands-off loads a fort, then runs the Godot project (also hidden) with
# DF3D_SCREENSHOT set; the world_view script saves a frame after 5s and
# quits. Leaves a PNG for inspection; quits DF afterwards.
#
# Containment (Df3dLane.psm1): DF and Godot both run in this
# process's kill-on-close job object; prefs are staged silent + windowed.
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { "C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress" }),
    [string]$GodotExe = $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" }),
    [int]$Port = 5010,
    [string]$ScreenshotOut = "",
    [int]$BootTimeoutSec = 420,
    [int]$GodotTimeoutSec = 90
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($ScreenshotOut -eq "") { $ScreenshotOut = Join-Path $repo "build\godot_render_check.png" }
$projectDir = Join-Path $repo "presentations\godot\project"

if (-not (Test-Path $GodotExe)) { Write-Host "[render-check] FAIL: Godot not found at $GodotExe" -ForegroundColor Red; exit 1 }

try {
    Enter-Df3dLane -DfPath $DfPath -Port $Port
} catch {
    Write-Host "[render-check] FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

$ok = $false
try {
    # --- boot DF hidden and reach a fort ---
    Set-DfPrefs
    Install-DfSmokeScript -DfPath $DfPath -SourceDir $PSScriptRoot
    $dfProc = Start-Df3d -DfPath $DfPath
    $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    if ($boot -eq 'exited') { Write-Host "[render-check] FAIL: DF exited during boot" -ForegroundColor Red; exit 1 }
    if ($boot -eq 'timeout') { Write-Host "[render-check] FAIL: fort did not load" -ForegroundColor Red; exit 1 }
    # DF re-asserts pause after load; unpause so the scene is alive (moving
    # units, advancing ticks) when the frame is captured.
    Invoke-Dfhack @("lua", "df.global.pause_state=false") -Quiet | Out-Null
    Write-Host "[render-check] fort loaded and unpaused; launching Godot (hidden) for screenshot"

    # --- run Godot hidden with the screenshot hook ---
    if (Test-Path $ScreenshotOut) { Remove-Item $ScreenshotOut -Force }
    $env:DF3D_SCREENSHOT = $ScreenshotOut
    $gProc = Start-ContainedProcess -Exe $GodotExe -Arguments "--path `"$projectDir`"" -WorkingDir $projectDir
    if (-not $gProc.WaitForExit($GodotTimeoutSec * 1000)) {
        Write-Host "[render-check] Godot did not quit within $GodotTimeoutSec s; killing pid $($gProc.Id)"
        Stop-Process -Id $gProc.Id -Force -Confirm:$false -ErrorAction SilentlyContinue
    }
    $ok = Test-Path $ScreenshotOut
} finally {
    Exit-Df3dLane
}

if ($ok) {
    Write-Host "[render-check] PASS: screenshot at $ScreenshotOut"
    exit 0
}
Write-Host "[render-check] FAIL: no screenshot produced"
exit 1
