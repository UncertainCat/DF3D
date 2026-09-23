# DF3D entity probe lane: boots DF hands-off through
# Df3dLane.psm1 (job-contained, single occupancy), lets the fort run
# for -RunSec so hauling is under way, pauses, runs df3d-entity-probe.lua
# (building stage / extents / civzone / item flag facts) and `df3d status`,
# and writes everything to -Out. Never saves. Stops DF via dfhack die.
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { "C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress" }),
    [int]$Port = 5010,
    [int]$BootTimeoutSec = 420,
    [int]$RunSec = 15,
    [string]$Out = "",
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Out -eq "") { $Out = Join-Path $repo "build\entity_probe.log" }
$dfhackRun = Join-Path $DfPath "hack\dfhack-run.exe"
$probeDst = Join-Path $DfPath "hack\scripts\df3d-entity-probe.lua"

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
    Copy-Item (Join-Path $PSScriptRoot "df3d-entity-probe.lua") $probeDst -Force
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

    Invoke-Dfhack @("lua", "df.global.pause_state = false") -Quiet | Out-Null
    Start-Sleep -Seconds $RunSec
    Invoke-Dfhack @("lua", "df.global.pause_state = true") -Quiet | Out-Null

    Capture @("df3d-entity-probe")
    Capture @("df3d", "status")
    Write-Host "[probe] output: $Out"
} finally {
    if (Test-Path $probeDst) { Remove-Item $probeDst -Force -ErrorAction SilentlyContinue }
    Exit-Df3dLane
}
Write-Host "[probe] PASS" -ForegroundColor Green
exit 0
