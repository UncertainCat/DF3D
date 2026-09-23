# Offline tier-2/4 lane for the Godot presentation: runs the project HIDDEN
# and job-contained (Df3dLane.psm1) in fixture replay mode
# (DF3D_FIXTURE) with the screenshot hook, waits for it to quit, and leaves
# a PNG plus a <png>.txt stats line (top z, units by how they are drawn --
# composited / simple / cubes -- composite cache and build counts, blocks,
# faces, textured / placeholder counts, build time, and godot_errors) and
# a <png>.godot.log with Godot's own output / error log. No DF involved;
# safe to run any time the extension is built and no Godot editor holds
# the DLL.
#
#   tools/smoke/godot_fixture_shot.ps1 -Fixture fixtures/synthetic/demo_fort.df3dfix -TopZ 5
param(
    [string]$Fixture = "fixtures/synthetic/demo_fort.df3dfix",
    [int]$TopZ = -1,
    [int]$Window = -1,
    [double]$FixedTick = -1,
    [switch]$Reveal,
    # Camera hooks for close-ups (tier 4): focus "x,y,z" in DF tile coords,
    # distance in tiles, pitch/yaw in radians (pitch negative looks down).
    [string]$Focus = "",
    [double]$CamDist = -1,
    [string]$CamPitch = "",
    [string]$CamYaw = "",
    # Camera eye at this DF tile ("x,y,z"; pitch / yaw kept): inside a wall,
    # under a floor. The Godot log names the tile the eye is in.
    [string]$CamPos = "",
    [string]$Out = "",
    # Tier-4 composite dump: write unit composites (PNG per unit,
    # composites.txt listing, composites_sheet.png) under this directory
    # once every visible unit's sprite is built; -DumpIds "id,id" picks
    # units (default: up to -DumpMax present units with distinct stacks).
    [string]$DumpComposites = "",
    [string]$DumpIds = "",
    [int]$DumpMax = 24,
    [double]$CompositeBudgetMs = -1,
    [string]$GodotExe = $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" }),
    [int]$TimeoutSec = 120,
    [switch]$Visible
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$projectDir = Join-Path $repo "presentations\godot\project"
$fixturePath = if ([System.IO.Path]::IsPathRooted($Fixture)) { $Fixture } else { Join-Path $repo $Fixture }
if (-not (Test-Path $fixturePath)) { Write-Host "[fixture-shot] FAIL: fixture not found: $fixturePath" -ForegroundColor Red; exit 1 }
if (-not (Test-Path $GodotExe)) { Write-Host "[fixture-shot] FAIL: Godot not found at $GodotExe" -ForegroundColor Red; exit 1 }
if ($Out -eq "") {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($fixturePath)
    $suffix = if ($TopZ -ge 0) { "_z$TopZ" } else { "" }
    $Out = Join-Path $repo "build\godot_fixture_${name}${suffix}.png"
}
if (-not [System.IO.Path]::IsPathRooted($Out)) { $Out = Join-Path (Get-Location) $Out }
$stats = "$Out.txt"
if (Test-Path $Out) { Remove-Item $Out -Force }
if (Test-Path $stats) { Remove-Item $stats -Force }

$env:DF3D_FIXTURE = $fixturePath
$env:DF3D_SCREENSHOT = $Out
$env:DF3D_TOP_Z = if ($TopZ -ge 0) { "$TopZ" } else { "" }
$env:DF3D_WINDOW = if ($Window -gt 0) { "$Window" } else { "" }
$env:DF3D_FIXTURE_TICK = if ($FixedTick -ge 0) { "$FixedTick" } else { "" }
$env:DF3D_REVEAL = if ($Reveal) { "1" } else { "" }
$env:DF3D_CAM_FOCUS = $Focus
$env:DF3D_CAM_DIST = if ($CamDist -gt 0) { "$CamDist" } else { "" }
$env:DF3D_CAM_PITCH = $CamPitch
$env:DF3D_CAM_YAW = $CamYaw
$env:DF3D_CAM_POS = $CamPos
if ($DumpComposites -ne "" -and -not [System.IO.Path]::IsPathRooted($DumpComposites)) { $DumpComposites = Join-Path $repo $DumpComposites }
$env:DF3D_DUMP_COMPOSITES = $DumpComposites
$env:DF3D_DUMP_IDS = $DumpIds
$env:DF3D_DUMP_MAX = "$DumpMax"
$env:DF3D_COMPOSITE_BUDGET = if ($CompositeBudgetMs -ge 0) { "$CompositeBudgetMs" } else { "" }
# Godot's stdout/stderr go nowhere on the hidden desktop (the process has
# no console and no redirected handles), so GDScript errors, push_error
# and the extension's printerr were invisible.
# --log-file makes Godot write its output/error log to a sidecar next to
# the screenshot; error lines are echoed after the run and counted into
# the stats line.
$godotLog = "$Out.godot.log"
if (Test-Path $godotLog) { Remove-Item $godotLog -Force }
$godotArgs = "--path `"$projectDir`" --log-file `"$godotLog`""
Write-Host "[fixture-shot] fixture=$fixturePath topZ=$TopZ window=$Window fixedTick=$FixedTick reveal=$($Reveal.IsPresent)"
$gProc = Start-ContainedProcess -Exe $GodotExe -Arguments $godotArgs -WorkingDir $projectDir -Visible:$Visible
if (-not $gProc.WaitForExit($TimeoutSec * 1000)) {
    Write-Host "[fixture-shot] Godot did not quit within $TimeoutSec s; killing pid $($gProc.Id)"
    Stop-Process -Id $gProc.Id -Force -Confirm:$false -ErrorAction SilentlyContinue
}
$errorLines = @()
if (Test-Path $godotLog) {
    $errorLines = @(Get-Content $godotLog | Where-Object { $_ -match '^(ERROR|SCRIPT ERROR|USER ERROR|USER SCRIPT ERROR)\b|^\s+at:' })
    if ($errorLines.Count -gt 0) {
        Write-Host "[fixture-shot] Godot reported $($errorLines.Count) error line(s) ($godotLog):" -ForegroundColor Yellow
        $errorLines | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
    }
} else {
    Write-Host "[fixture-shot] warning: Godot wrote no log at $godotLog"
}
if (Test-Path $stats) {
    # The stats line is written by world_view.gd; the lane appends what only
    # it can see (the error count), so regressions stay visible in text.
    $line = (Get-Content $stats | Select-Object -First 1) + " godot_errors=$($errorLines.Count)"
    Set-Content -Path $stats -Value $line -Encoding ascii
    Write-Host "    $line"
}
if (Test-Path $Out) { Write-Host "[fixture-shot] PASS: $Out"; exit 0 }
Write-Host "[fixture-shot] FAIL: no screenshot produced"
exit 1
