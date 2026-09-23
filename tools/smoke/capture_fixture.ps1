# DF3D recorded-fixture capture lane (fixture library).
#
# Same containment and boot path as live_smoke.ps1 (Df3dLane.psm1):
# boots DF+DFHack hands-off on a hidden desktop, starts recording through
# the bridge (the first entry is a Full terrain snapshot built from the
# terrain grid), runs the live_client smoke (which unpauses, does
# the SetPause round-trip mid-stream, and waits for a terrain Delta), then
# keeps the sim running until the recording spans at least -Ticks sim
# ticks, stops recording, validates the file through the inspector and
# copies it to -Out.
#
# Never saves the game. Stops DF via dfhack die.
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { "C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress" }),
    [int]$Port = 5010,
    [int]$Ticks = 2000,
    [string]$Out = "",
    [int]$BootTimeoutSec = 420,
    [int]$RunTimeoutSec = 600,
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Out -eq "") { $Out = Join-Path $repo "fixtures\recorded\capture.df3dfix" }
$tmp = Join-Path $repo "fixtures\recorded\capture_in_progress.df3dfix"
$liveClient = Join-Path $repo "build\tools\live_client.exe"
$inspector = Join-Path $repo "build\consumers\inspector\inspector.exe"
$dfhackRun = Join-Path $DfPath "hack\dfhack-run.exe"

function Fail($msg) { Write-Host "[capture] FAIL: $msg" -ForegroundColor Red; Exit-Df3dLane; exit 1 }

function Get-FrameCounter {
    $r = Invoke-DfhackRaw @("lua", "print(df.global.world.frame_counter)")
    if ($r.ExitCode -ne 0) { return -1 }
    $line = ($r.Output | Where-Object { $_ -match '^\d+$' } | Select-Object -Last 1)
    if ($line) { return [int]$line } else { return -1 }
}

foreach ($p in @($dfhackRun, (Join-Path $DfPath "dfhooks.dll"), (Join-Path $DfPath "hack\plugins\df3d.plug.dll"))) {
    if (-not (Test-Path $p)) { Write-Host "[capture] FAIL: missing $p" -ForegroundColor Red; exit 1 }
}
foreach ($p in @($liveClient, $inspector)) {
    if (-not (Test-Path $p)) { Write-Host "[capture] FAIL: missing $p (build the DF3D repo first)" -ForegroundColor Red; exit 1 }
}
if (Get-Process steam -ErrorAction SilentlyContinue) {
    Write-Host "[capture] WARNING: Steam client is running; it can auto-apply DF updates and break the version pin (see PINS.md)" -ForegroundColor Yellow
}

try {
    Enter-Df3dLane -DfPath $DfPath -Port $Port
} catch {
    Write-Host "[capture] FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

try {
    Set-DfPrefs
    Install-DfSmokeScript -DfPath $DfPath -SourceDir $PSScriptRoot

    $dfProc = Start-Df3d -DfPath $DfPath -Visible:$Visible
    $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    if ($boot -eq 'exited' -and -not $Visible) {
        Write-Host "[capture] WARNING: DF exited during boot on the hidden desktop; retrying visible" -ForegroundColor Yellow
        $dfProc = Start-Df3d -DfPath $DfPath -Visible
        $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    }
    if ($boot -eq 'exited') { Fail "DF exited during boot (exit $($dfProc.ExitCode))" }
    if ($boot -eq 'timeout') { Fail "fort did not load within $BootTimeoutSec s" }
    Write-Host "[capture] fort loaded"

    Invoke-Dfhack @("df3d", "status") | Out-Null

    New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null
    if (Test-Path $tmp) { Remove-Item $tmp -Force }
    $startFrame = Get-FrameCounter
    if ((Invoke-Dfhack @("df3d", "record", "start", $tmp)) -ne 0) { Fail "df3d record start failed" }
    Write-Host "[capture] recording from frame $startFrame"

    # Same hands-off dig designation as live_smoke: guarantees a Delta.
    $designate = @'
local u = df.global.world.units.active[0]
local p = xyz2pos(u.pos.x, u.pos.y, u.pos.z - 1)
local b = dfhack.maps.getTileBlock(p)
if b then
  b.designation[p.x % 16][p.y % 16].dig = df.tile_dig_designation.Default
  b.flags.designated = true
  print(('df3d-smoke: designated dig at %d,%d,%d'):format(p.x, p.y, p.z))
end
'@ -replace "`r", ""
    Invoke-Dfhack @("lua", $designate) | Out-Null

    & $liveClient smoke --expect-terrain-delta --expect-item-delta --expect-corpses --expect-webs
    if ($LASTEXITCODE -ne 0) { Fail "live_client smoke failed (exit $LASTEXITCODE)" }

    # Keep the sim running (the smoke leaves it unpaused) until enough ticks.
    $deadline = (Get-Date).AddSeconds($RunTimeoutSec)
    $frame = Get-FrameCounter
    while (($frame -lt 0 -or ($frame - $startFrame) -lt $Ticks) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $dfProc.Refresh()
        if ($dfProc.HasExited) { Fail "DF exited during capture" }
        $frame = Get-FrameCounter
        Write-Host "[capture] frame $frame (+$($frame - $startFrame))"
    }
    if (($frame - $startFrame) -lt $Ticks) { Write-Host "[capture] WARNING: only $($frame - $startFrame) ticks captured in $RunTimeoutSec s" -ForegroundColor Yellow }

    if ((Invoke-Dfhack @("df3d", "record", "stop")) -ne 0) { Fail "df3d record stop failed" }
    Invoke-Dfhack @("df3d", "status") | Out-Null

    if (-not (Test-Path $tmp)) { Fail "bridge produced no fixture at $tmp" }
    $report = & $inspector $tmp 2>&1
    $inspExit = $LASTEXITCODE
    $report | Select-Object -First 8 | ForEach-Object { Write-Host "    $_" }
    if ($inspExit -ne 0) { Fail "recorded fixture failed validation" }
    Move-Item $tmp $Out -Force
    $size = (Get-Item $Out).Length
    Write-Host "[capture] fixture validated: $Out ($([math]::Round($size / 1MB, 1)) MB)"
} finally {
    Exit-Df3dLane
}
Write-Host "[capture] PASS" -ForegroundColor Green
exit 0
