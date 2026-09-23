# Diagnostic variant of live_smoke: boot to fort on the hidden desktop,
# interrogate the df3d plugin verbosely, then KEEP DF RUNNING for follow-up
# probing from another shell (hack\dfhack-run.exe <cmd>) until -HoldSec
# elapses, Ctrl+C is pressed, or DF exits.
#
# Containment (Df3dLane.psm1): DF lives in this process's job
# object, so "keep running" means this script stays alive to hold it.
# Closing this window, killing this task, or hitting the hold limit all
# end DF. It cannot be left playing music on an invisible desktop.
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { "C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress" }),
    [int]$Port = 5010,
    [int]$BootTimeoutSec = 420,
    [int]$HoldSec = 900,
    [switch]$Visible
)
$ErrorActionPreference = 'Continue'
Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

function Probe([string[]]$cmdArgs) {
    Write-Host ">>> dfhack-run $($cmdArgs -join ' ')"
    $code = Invoke-Dfhack $cmdArgs -Retries 1
    Write-Host "    (exit $code)"
}

try {
    Enter-Df3dLane -DfPath $DfPath -Port $Port
} catch {
    Write-Host "[debug] FAIL: $($_.Exception.Message)" -ForegroundColor Red; exit 1
}

try {
    Set-DfPrefs
    Install-DfSmokeScript -DfPath $DfPath -SourceDir $PSScriptRoot
    $proc = Start-Df3d -DfPath $DfPath -Visible:$Visible
    $boot = Wait-DfFort -TimeoutSec $BootTimeoutSec
    if ($boot -eq 'exited') { Write-Host "[debug] DF exited during boot (code $($proc.ExitCode))"; exit 1 }
    if ($boot -eq 'timeout') { Write-Host "[debug] fort did not load in time"; exit 1 }
    Write-Host "[debug] fort loaded; probing plugin"

    Probe @("plug", "df3d")
    Probe @("df3d", "status")
    Probe @("enable", "df3d")
    Probe @("df3d", "status")
    Probe @("df3d", "record", "start", "$repo\fixtures\recorded\debug_capture.df3dfix")
    Probe @("df3d", "status")
    Probe @("lua", "print(df.global.world.frame_counter)")

    Write-Host "[debug] holding DF (pid $($proc.Id)) for up to $HoldSec s; probe it with hack\dfhack-run.exe, Ctrl+C here to end"
    $deadline = (Get-Date).AddSeconds($HoldSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $proc.Refresh()
        if ($proc.HasExited) { Write-Host "[debug] DF exited on its own (code $($proc.ExitCode))"; break }
    }
    if (-not $proc.HasExited) { Write-Host "[debug] hold limit reached" }
} finally {
    Exit-Df3dLane
    Write-Host "[debug] done; DF stopped and staging removed"
}
