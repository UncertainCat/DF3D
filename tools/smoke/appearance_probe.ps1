# DF3D appearance probe lane (fidelity check).
#
# Boots DF+DFHack hands-off through Df3dLane.psm1 (job-contained, single
# occupancy), lets the fort load, then runs the df3d plugin's
# appearance diagnostics and writes their output to -Out:
#   df3d appearance pages            texpos map / page table sanity
#   df3d appearance layersets first  the chosen layer set's raw layer table
#   df3d appearance first verify     one dwarf's resolved stack vs DF's own
#                                    cached composite, pixel-wise
#   df3d appearance survey <n>       fidelity survey over n units (+ the
#                                    random-part calibration table)
#   df3d status                      per-frame cost including appearance
# Never saves. Stops DF via dfhack die.
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { "C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress" }),
    [int]$Port = 5010,
    [int]$BootTimeoutSec = 420,
    [int]$SurveyUnits = 60,
    [int]$RunSec = 20,
    [string]$Out = "",
    [string]$Unit = "first",
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Out -eq "") { $Out = Join-Path $repo "build\appearance_probe.log" }
$dfhackRun = Join-Path $DfPath "hack\dfhack-run.exe"

function Fail($msg) { Write-Host "[probe] FAIL: $msg" -ForegroundColor Red; Exit-Df3dLane; exit 1 }

function Capture([string[]]$cmdArgs) {
    $r = Invoke-DfhackRaw $cmdArgs
    Add-Content -Path $Out -Value ("=== dfhack-run " + ($cmdArgs -join ' ') + " (exit $($r.ExitCode))")
    $r.Output | ForEach-Object { Add-Content -Path $Out -Value $_ }
    Write-Host "[probe] $($cmdArgs -join ' '): $($r.Output.Count) lines (exit $($r.ExitCode))"
}

foreach ($p in @($dfhackRun, (Join-Path $DfPath "hack\plugins\df3d.plug.dll"))) {
    if (-not (Test-Path $p)) { Write-Host "[probe] FAIL: missing $p" -ForegroundColor Red; exit 1 }
}

try {
    Enter-Df3dLane -DfPath $DfPath -Port $Port
} catch {
    Write-Host "[probe] FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

try {
    Set-DfPrefs
    Install-DfSmokeScript -DfPath $DfPath -SourceDir $PSScriptRoot
    $dfProc = Start-Df3d -DfPath $DfPath -Visible:$Visible
    $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    if ($boot -eq 'exited' -and -not $Visible) {
        Write-Host "[probe] WARNING: DF exited during boot on the hidden desktop; retrying visible" -ForegroundColor Yellow
        $dfProc = Start-Df3d -DfPath $DfPath -Visible
        $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    }
    if ($boot -eq 'exited') { Fail "DF exited during boot (exit $($dfProc.ExitCode))" }
    if ($boot -eq 'timeout') { Fail "fort did not load within $BootTimeoutSec s" }
    Write-Host "[probe] fort loaded"

    if (Test-Path $Out) { Remove-Item $Out -Force }
    New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null

    # Let the sim run a little so DF has drawn (and cached) unit textures
    # and the bridge has resolved every unit at least once.
    Invoke-Dfhack @("lua", "df.global.pause_state = false") -Quiet | Out-Null
    Start-Sleep -Seconds $RunSec
    Invoke-Dfhack @("lua", "df.global.pause_state = true") -Quiet | Out-Null

    # Center the map view on the probed unit so DF draws it (the verify
    # oracle reads the composite DF renders into the main viewport).
    $center = @'
local target = nil
for _, u in ipairs(df.global.world.units.active) do
  if dfhack.units.isActive(u) and not dfhack.units.isDead(u) and dfhack.units.isCitizen(u) then target = u break end
end
if target then
  dfhack.gui.revealInDwarfmodeMap(xyz2pos(target.pos.x, target.pos.y, target.pos.z), true)
  print(('centered on unit %d at %d,%d,%d'):format(target.id, target.pos.x, target.pos.y, target.pos.z))
end
'@ -replace "`r", ""
    if ($Unit -ne "first") {
        $center = $center -replace "local target = nil", "local target = df.unit.find($Unit)"
        $center = $center -replace "for _, u in ipairs\(df.global.world.units.active\) do", "for _, u in ipairs({}) do"
    }
    Invoke-Dfhack @("lua", $center) | Out-Null
    Start-Sleep -Seconds 3

    Capture @("df3d", "appearance", "pages")
    Capture @("df3d", "appearance", "layersets", $Unit, "80")
    Capture @("df3d", "appearance", $Unit, "verify", (Join-Path $repo "build"))
    Capture @("df3d", "appearance", "layersets", $Unit, "40", "HELM")
    Capture @("df3d", "appearance", $Unit, "trace", "HOOD")
    Capture @("df3d", "appearance", $Unit, "trace", "COMBED_BLACK")
    Capture @("df3d", "appearance", $Unit, "trace", "*tissue")
    Capture @("df3d", "appearance", "survey", "$SurveyUnits")
    Capture @("df3d", "status")
    Write-Host "[probe] output: $Out"
} finally {
    Exit-Df3dLane
}
Write-Host "[probe] PASS" -ForegroundColor Green
exit 0
