# DF3D classic glyph probe lane: the classic tile and colour per item kind.
# Boots DF hands-off through Df3dLane.psm1 with [USE_CLASSIC_ASCII:YES] staged,
# loads the fort and records df3d-glyph-probe kinds / pick / center / cell /
# calib output to -Out. Never saves. Stops DF via dfhack die.
#   powershell -File tools\smoke\classic_glyph_probe.ps1
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { "C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress" }),
    [int]$Port = 5010,
    [int]$BootTimeoutSec = 420,
    [int]$Samples = 4,
    [int]$MaxCells = 60,
    [string]$Out = "",
    [switch]$NoAscii,
    [switch]$CellsOnly,
    [switch]$Visible
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if ($Out -eq "") { $Out = Join-Path $repo "build\classic_glyph_probe.log" }
$dfhackRun = Join-Path $DfPath "hack\dfhack-run.exe"
$probeDst = Join-Path $DfPath "hack\scripts\df3d-glyph-probe.lua"

function Fail($msg) { Write-Host "[glyph-probe] FAIL: $msg" -ForegroundColor Red; Exit-Df3dLane; exit 1 }

function Capture([string[]]$cmdArgs) {
    $r = Invoke-DfhackRaw $cmdArgs
    Add-Content -Path $Out -Value ("=== dfhack-run " + ($cmdArgs -join ' ') + " (exit $($r.ExitCode))")
    $r.Output | ForEach-Object { Add-Content -Path $Out -Value $_ }
    Write-Host "[glyph-probe] $($cmdArgs -join ' '): $($r.Output.Count) lines (exit $($r.ExitCode))"
    return $r
}

foreach ($p in @($dfhackRun, (Join-Path $DfPath "hack\plugins\df3d.plug.dll"))) {
    if (-not (Test-Path $p)) { Write-Host "[glyph-probe] FAIL: missing $p" -ForegroundColor Red; exit 1 }
}

try {
    Enter-Df3dLane -DfPath $DfPath -Port $Port
} catch {
    Write-Host "[glyph-probe] FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

try {
    Set-DfPrefs -ClassicAscii:(-not $NoAscii)
    Install-DfSmokeScript -DfPath $DfPath -SourceDir $PSScriptRoot
    Copy-Item (Join-Path $PSScriptRoot "df3d-glyph-probe.lua") $probeDst -Force
    $dfProc = Start-Df3d -DfPath $DfPath -Visible:$Visible
    $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    if ($boot -eq 'exited' -and -not $Visible) {
        Write-Host "[glyph-probe] WARNING: DF exited during boot on the hidden desktop; retrying visible" -ForegroundColor Yellow
        $dfProc = Start-Df3d -DfPath $DfPath -Visible
        $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    }
    if ($boot -eq 'exited') { Fail "DF exited during boot (exit $($dfProc.ExitCode))" }
    if ($boot -eq 'timeout') { Fail "fort did not load within $BootTimeoutSec s" }
    Write-Host "[glyph-probe] fort loaded"

    if (Test-Path $Out) { Remove-Item $Out -Force }
    New-Item -ItemType Directory -Force (Split-Path $Out) | Out-Null

    Invoke-Dfhack @("lua", "df.global.pause_state = true") -Quiet | Out-Null
    Capture @("lua", "print('classic ascii: ' .. tostring(df.global.init.display.flag.USE_GRAPHICS == false) .. ' (init USE_GRAPHICS ' .. tostring(df.global.init.display.flag.USE_GRAPHICS) .. ')')") | Out-Null
    if (-not $CellsOnly) { Capture @("df3d-glyph-probe", "kinds", "$Samples") | Out-Null }

    $r = Capture @("df3d-glyph-probe", "pick")
    $picks = @($r.Output | Where-Object { $_ -match '^pick (\d+):' })
    $count = [math]::Min($picks.Count, $MaxCells)
    Capture @("df3d-glyph-probe", "calib") | Out-Null
    Start-Sleep -Seconds 2
    Capture @("df3d-glyph-probe", "calib") | Out-Null
    for ($i = 0; $i -lt $count; $i++) {
        Capture @("df3d-glyph-probe", "center", "$i") | Out-Null
        Start-Sleep -Seconds 2
        Capture @("df3d-glyph-probe", "cell", "$i") | Out-Null
    }
    Write-Host "[glyph-probe] output: $Out"
} finally {
    if (Test-Path $probeDst) { Remove-Item $probeDst -Force -ErrorAction SilentlyContinue }
    Exit-Df3dLane
}
Write-Host "[glyph-probe] PASS" -ForegroundColor Green
exit 0
