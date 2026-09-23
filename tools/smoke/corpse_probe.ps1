# DF3D corpse probe lane: verifies corpse appearance stacks, corpse-piece
# drawing rules and glyph tables against DF's own textures and raws.
# Boots DF hands-off through Df3dLane.psm1, runs -RunSec, then surveys the
# corpse-heavy z levels, lone corpses/pieces and (unless -NoKill) two fresh
# corpses via df3d-corpse-probe.lua. Output goes to -Out. Never saves.
#   powershell -File tools\smoke\corpse_probe.ps1
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { "C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress" }),
    [int]$Port = 5010,
    [int]$BootTimeoutSec = 420,
    [int]$RunSec = 20,
    [int]$Levels = 3,
    [int]$SurveyItems = 80,
    [int]$LoneCorpses = 4,
    [int]$LonePieces = 12,
    [int]$KillSec = 8,
    [switch]$NoKill,
    [switch]$KillOnly,
    [string]$Out = "",
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Out -eq "") { $Out = Join-Path $repo "build\corpse_probe.log" }
$dfhackRun = Join-Path $DfPath "hack\dfhack-run.exe"
$probeDst = Join-Path $DfPath "hack\scripts\df3d-corpse-probe.lua"

function Fail($msg) { Write-Host "[probe] FAIL: $msg" -ForegroundColor Red; Exit-Df3dLane; exit 1 }

function Capture([string[]]$cmdArgs) {
    $r = Invoke-DfhackRaw $cmdArgs
    Add-Content -Path $Out -Value ("=== dfhack-run " + ($cmdArgs -join ' ') + " (exit $($r.ExitCode))")
    $r.Output | ForEach-Object { Add-Content -Path $Out -Value $_ }
    Write-Host "[probe] $($cmdArgs -join ' '): $($r.Output.Count) lines (exit $($r.ExitCode))"
    return $r
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
    Copy-Item (Join-Path $PSScriptRoot "df3d-corpse-probe.lua") $probeDst -Force
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

    # Let the sim run so DF draws (and caches) textures and the bridge has
    # resolved every corpse at least once.
    Invoke-Dfhack @("lua", "df.global.pause_state = false") -Quiet | Out-Null
    Start-Sleep -Seconds $RunSec
    Invoke-Dfhack @("lua", "df.global.pause_state = true") -Quiet | Out-Null

    if ($KillOnly) { $Levels = 0; $LoneCorpses = 0; $LonePieces = 0 }
    Capture @("df3d-corpse-probe", "levels", "$Levels") | Out-Null
    for ($i = 0; $i -lt $Levels; $i++) {
        # Center the view on the i-th densest corpse level; DF redraws on
        # the next frames even while paused, which fills the viewport's
        # item cells the survey reads.
        $r = Capture @("df3d-corpse-probe", "center", "$i")
        Start-Sleep -Seconds 3
        Capture @("df3d", "corpse", "survey", "$SurveyItems") | Out-Null
        if ($i -eq 0) { Capture @("df3d", "corpse", "first", "verify", (Join-Path $repo "build")) | Out-Null }
    }
    # Whole corpses alone on their tile (the cell is unambiguous), fresh
    # ones first: the skeleton rule and the CORPSE stack against DF's cell.
    $r = Capture @("df3d-corpse-probe", "lone")
    $lone = @($r.Output | Where-Object { $_ -match '^lone (\d+):' })
    for ($i = 0; $i -lt [math]::Min($lone.Count, $LoneCorpses); $i++) {
        Capture @("df3d-corpse-probe", "lone", "$i") | Out-Null
        Start-Sleep -Seconds 3
        Capture @("df3d", "corpse", "survey", "12") | Out-Null
        Capture @("df3d", "corpse", "first", "verify", (Join-Path $repo "build")) | Out-Null
    }
    # Corpse pieces alone on their tile, one per (flags, tissue) group.
    $r = Capture @("df3d-corpse-probe", "lonepiece")
    $lonep = @($r.Output | Where-Object { $_ -match '^lonepiece (\d+):' })
    for ($i = 0; $i -lt [math]::Min($lonep.Count, $LonePieces); $i++) {
        Capture @("df3d-corpse-probe", "lonepiece", "$i") | Out-Null
        Start-Sleep -Seconds 3
        Capture @("df3d", "corpse", "survey", "8") | Out-Null
    }
    if (-not $NoKill) {
        # Fresh corpses: bleed out one dwarf and one animal (never saved),
        # run a few seconds so they die and DF draws the corpses, then the
        # CORPSE-set oracle on each.
        Capture @("df3d-corpse-probe", "kill") | Out-Null
        Invoke-Dfhack @("lua", "df.global.pause_state = false") -Quiet | Out-Null
        Start-Sleep -Seconds $KillSec
        Invoke-Dfhack @("lua", "df.global.pause_state = true") -Quiet | Out-Null
        $r = Capture @("df3d-corpse-probe", "killed")
        $killed = @($r.Output | Where-Object { $_ -match '^killed (\d+): corpse item (\d+) ' } | ForEach-Object { $Matches[2] })
        for ($i = 0; $i -lt $killed.Count; $i++) {
            Capture @("df3d-corpse-probe", "killed", "$i") | Out-Null
            Start-Sleep -Seconds 3
            Capture @("df3d", "corpse", "survey", "40") | Out-Null
            Capture @("df3d", "corpse", "$($killed[$i])", "verify", (Join-Path $repo "build")) | Out-Null
        }
    }
    Capture @("df3d-corpse-probe", "pieces") | Out-Null
    Capture @("df3d", "glyphs", "16") | Out-Null
    Capture @("df3d-corpse-probe", "glyphs") | Out-Null
    Capture @("df3d", "status") | Out-Null
    Write-Host "[probe] output: $Out"
} finally {
    if (Test-Path $probeDst) { Remove-Item $probeDst -Force -ErrorAction SilentlyContinue }
    Exit-Df3dLane
}
Write-Host "[probe] PASS" -ForegroundColor Green
exit 0
