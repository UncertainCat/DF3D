# Owned, never-saved pointer acceptance against the terrain oracle's verified fortress.
param([Parameter(Mandatory=$true)][string]$SavePath,
 [Parameter(Mandatory=$true)][string]$OwnedSaveManifest)
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
$env:Path='C:/msys64/mingw64/bin;'+$env:Path
$dfPath='C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'
Import-Module "$repo/tools/smoke/Df3dLane.psm1" -Force
$clone=(Resolve-Path -LiteralPath $SavePath).Path.Replace('\','/')
$expected=(Get-Content -LiteralPath $OwnedSaveManifest -Raw).TrimEnd("`r","`n")
function Manifest {
 return (@(Get-ChildItem -LiteralPath $clone -Recurse -File | ForEach-Object {
  $_.FullName.Substring($clone.Length).TrimStart('\','/')+' '+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
 } | Sort-Object) -join "`n")
}
if((Manifest) -cne $expected){throw 'Owned source differs from verified manifest'}
$out="$repo/build/tile-hover-live-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
$entered=$false;$summary='failed'
try {
 Enter-Df3dLane -DfPath $dfPath -Port 5010;$entered=$true
 Get-FileHash "$dfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/tests/tile_hover_live.gd",$PSCommandPath | ConvertTo-Json | Set-Content "$out/capture-inputs.json"
 Set-DfPrefs;Install-DfMenuStartup -DfPath $dfPath
 Start-Df3d -DfPath $dfPath | Out-Null
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'Source load failed'}
 $r=Invoke-DfhackRaw -CommandArgs @('lua','df.global.d_init.feature.autosave=df.d_init_autosave.NONE;assert(df.global.pause_state)')
 if($r.ExitCode -ne 0){throw 'Pause/autosave guard failed'}
 $env:DF3D_HOVER_ACCEPTANCE=$out;$env:DF3D_DF_PATH=$dfPath
 $project="$repo/presentations/godot/project"
 $g=Start-ContainedProcess -Visible -Exe 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' -Arguments "--path `"$project`" --script res://tests/tile_hover_live.gd --log-file `"$out/godot.log`"" -WorkingDir $project
 if(-not $g.WaitForExit(240000)){Stop-Process -Id $g.Id -Force;throw 'Viewer timed out'}
 if($g.ExitCode -ne 0){throw "Viewer exit $($g.ExitCode)"}
 $result=Get-Content "$out/viewer-result.json" -Raw | ConvertFrom-Json
 if(-not $result.success){throw 'Viewer assertions failed'}
 $r=Invoke-DfhackRaw -CommandArgs @('lua','assert(df.global.pause_state);print("HOVER_PAUSED_FRAME",df.global.world.frame_counter)')
 $r | ConvertTo-Json | Set-Content "$out/final-state.json"
 if($r.ExitCode -ne 0){throw 'Final pause guard failed'}
 $summary='passed'
} catch {$summary='failed '+$_.Exception.Message}
finally {
 try {if($entered){Exit-Df3dLane}} catch {$summary='failed teardown '+$_.Exception.Message}
 try {if((Manifest) -cne $expected){throw 'Source changed'};'Owned source unchanged' | Set-Content "$out/save-preservation.txt"} catch {$summary='failed preservation '+$_.Exception.Message}
 $summary | Set-Content "$out/summary.txt";Write-Output "$summary -- $out"
}
if($summary -ne 'passed'){exit 1}
