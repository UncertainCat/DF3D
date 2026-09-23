# DF3D live smoke lane: boots DF+DFHack hands-off on a hidden desktop (falls
# back to visible, or -Visible), loads the latest fort save, exercises the
# mirror/command round trips through live_client, records and validates a
# bridge fixture, then stops DF via dfhack die (never saves).
# Contained by Df3dLane.psm1 (job object, single occupancy, prefs restored).
# Prereqs: pinned DFHack + df3d plugin installed into the DF dir.
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { "C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress" }),
    [int]$Port = 5010,
    [string]$FixtureOut = "",
    [int]$BootTimeoutSec = 420,
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($FixtureOut -eq "") { $FixtureOut = Join-Path $repo "fixtures\recorded\smoke_capture.df3dfix" }
$liveClient = Join-Path $repo "build\tools\live_client.exe"
$inspector = Join-Path $repo "build\consumers\inspector\inspector.exe"
$dfhackRun = Join-Path $DfPath "hack\dfhack-run.exe"

function Fail($msg) { Write-Host "[smoke] FAIL: $msg" -ForegroundColor Red; Exit-Df3dLane; exit 1 }

# --- preflight ---
foreach ($p in @($dfhackRun, (Join-Path $DfPath "dfhooks.dll"), (Join-Path $DfPath "hack\plugins\df3d.plug.dll"))) {
    if (-not (Test-Path $p)) { Write-Host "[smoke] FAIL: missing $p (DFHack + df3d plugin must be installed)" -ForegroundColor Red; exit 1 }
}
foreach ($p in @($liveClient, $inspector)) {
    if (-not (Test-Path $p)) { Write-Host "[smoke] FAIL: missing $p (build the DF3D repo first)" -ForegroundColor Red; exit 1 }
}
if (Get-Process steam -ErrorAction SilentlyContinue) {
    Write-Host "[smoke] WARNING: Steam client is running; it can auto-apply DF updates and break the version pin (see PINS.md)" -ForegroundColor Yellow
}

try {
    Enter-Df3dLane -DfPath $DfPath -Port $Port
} catch {
    Write-Host "[smoke] FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

try {
    # --- stage prefs + init + loader script ---
    Set-DfPrefs
    Install-DfSmokeScript -DfPath $DfPath -SourceDir $PSScriptRoot

    # --- launch (hidden desktop first unless -Visible), boot to fort ---
    $dfProc = Start-Df3d -DfPath $DfPath -Visible:$Visible
    $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    if ($boot -eq 'exited' -and -not $Visible) {
        Write-Host "[smoke] WARNING: DF exited during boot on the hidden desktop (exit $($dfProc.ExitCode)); retrying visible" -ForegroundColor Yellow
        $dfProc = Start-Df3d -DfPath $DfPath -Visible
        $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    }
    if ($boot -eq 'exited') { Fail "DF exited during boot (exit $($dfProc.ExitCode))" }
    if ($boot -eq 'timeout') { Fail "fort did not load within $BootTimeoutSec s" }
    Write-Host "[smoke] fort loaded; bridge should be publishing"

    # --- record a fixture while the smoke test runs ---
    New-Item -ItemType Directory -Force (Split-Path $FixtureOut) | Out-Null
    if (Test-Path $FixtureOut) { Remove-Item $FixtureOut -Force }
    if ((Invoke-Dfhack @("df3d", "record", "start", $FixtureOut)) -ne 0) { Fail "df3d record start failed" }

    # --- hands-off terrain change: designate the wall under the first
    # citizen for digging (a designation flag flip the bridge must publish
    # as a Delta; if reachable the dwarves dig it, a second Delta). Lanes
    # never save, so the fort is untouched. ---
    $designate = @'
local u = df.global.world.units.active[0]
local p = xyz2pos(u.pos.x, u.pos.y, u.pos.z - 1)
local b = dfhack.maps.getTileBlock(p)
if b then
  b.designation[p.x % 16][p.y % 16].dig = df.tile_dig_designation.Default
  b.flags.designated = true
  print(('df3d-smoke: designated dig at %d,%d,%d'):format(p.x, p.y, p.z))
else
  print('df3d-smoke: no block under first unit; skipping designation')
end
'@ -replace "`r", ""
    Invoke-Dfhack @("lua", $designate) | Out-Null

    # --- client-side verification: mirror live + SetPause round-trip +
    # terrain Full from the grid + at least one Delta ---
    # The mature fort has corpses of layered species and cavern
    # spider webs; both must arrive (corpse stacks, Web flag) with the glyph
    # tables.
    # The command round trips (designations, item / building flags,
    # a Rejected result, the 100x100 drain benchmark) run while the sim is
    # unpaused; nothing is saved, so the fort keeps none of it.
    & $liveClient smoke --expect-terrain-delta --expect-item-delta --expect-corpses --expect-webs --commands
    $smokeExit = $LASTEXITCODE

    if ((Invoke-Dfhack @("df3d", "record", "stop")) -ne 0) { Write-Host "[smoke] WARNING: record stop failed" -ForegroundColor Yellow }
    Invoke-Dfhack @("df3d", "status") | Out-Null

    if ($smokeExit -ne 0) { Fail "live_client smoke failed (exit $smokeExit)" }

    # --- validate the recorded fixture through the world model ---
    if (-not (Test-Path $FixtureOut)) { Fail "bridge produced no fixture at $FixtureOut" }
    # Capture fully, then truncate for display: piping a native command into
    # Select-Object -First kills the process early and fakes a failure exit.
    $report = & $inspector $FixtureOut 2>&1
    $inspExit = $LASTEXITCODE
    $report | Select-Object -First 6 | ForEach-Object { Write-Host "    $_" }
    if ($inspExit -ne 0) { Fail "recorded fixture failed validation" }
    Write-Host "[smoke] recorded fixture validated: $FixtureOut"
} finally {
    # Runs on success, Fail, Ctrl+C, and script errors alike. If the
    # process is killed outright instead, the job object does this part.
    Exit-Df3dLane
}
Write-Host "[smoke] PASS" -ForegroundColor Green
exit 0
