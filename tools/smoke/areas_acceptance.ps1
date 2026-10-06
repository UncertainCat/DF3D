# Protected, owned, never-saved acceptance. SaveId names a NEW disposable copy
# of region5; existing saves are refused. The copy is retained for inspection.
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SaveId,[switch]$Controller,[switch]$ControllerScene,[switch]$ControllerRestart,[switch]$BoundaryOnly,[switch]$MultiOnly,[switch]$PaintCountsOnly,[switch]$LocationScene,[switch]$StaffOnly,[switch]$StaffScene,[string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}))
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
$out="$repo/build/areas-acceptance-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
$summary='failed startup'; $entered=$false; $loaded=$false; $finalPaused=$false; $g=$null
$saveManifests=@{}
$oldInput=$env:DF3D_AREAS_ACCEPTANCE
$deadline=(Get-Date).AddSeconds(1800)
function Write-Lf([string]$Path,[string]$Text) {
 [IO.File]::WriteAllText($Path,($Text -replace "`r`n","`n"),[Text.UTF8Encoding]::new($false))
}
function Write-Ack([string]$Path,[string]$Text) {
 Write-Lf "$Path.tmp" $Text
 Move-Item -LiteralPath "$Path.tmp" -Destination $Path
}
function Save-Manifest([string]$Root) {
 $rows=@(Get-ChildItem -LiteralPath $Root -File -Recurse | ForEach-Object {
  $_.FullName.Substring($Root.Length).TrimStart('\','/')+' '+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
 } | Sort-Object)
 return ($rows -join "`n")
}
function Invoke-LuaFile([string]$Name,[string]$Arguments) {
 # Lua long strings prevent paths/SaveId from becoming executable Lua text.
 $r=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile([==[$repo/tools/smoke/$Name]==]))($Arguments)")
 $r.Output | Add-Content "$out/native.log"
 "exit=$($r.ExitCode) script=$Name" | Add-Content "$out/native.log"
 if($r.ExitCode -eq 124 -and ($r.Output -join "`n") -notmatch 'FIXTURE_(READY|INCOMPLETE)|SEMANTIC_(PASS|INCOMPLETE)|GUARD_(BASELINE|NATIVE_UNCHANGED)'){throw 'INCOMPLETE DFHack wait cap hit'}
 return $r
}
try {
 if($StaffScene){$StaffOnly=$true;Write-Lf "$out/staff-scene.txt" 'viewport'}
 if($StaffOnly -and ($Controller -or $ControllerScene -or $ControllerRestart -or $BoundaryOnly -or $MultiOnly -or $PaintCountsOnly -or $LocationScene)){throw 'StaffOnly is a separate protected semantic lane'}
 if($LocationScene -and ($Controller -or $ControllerScene -or $ControllerRestart -or $BoundaryOnly -or $MultiOnly -or $PaintCountsOnly)){throw 'LocationScene is a separate protected GPU lane'}
 if($PaintCountsOnly -and ($Controller -or $ControllerScene -or $ControllerRestart -or $BoundaryOnly -or $MultiOnly)){throw 'PaintCountsOnly is a separate headless protocol/controller lane'}
 if($BoundaryOnly -and (-not $ControllerScene -or $ControllerRestart)){throw 'BoundaryOnly requires ControllerScene without ControllerRestart'}
 if($MultiOnly -and ($BoundaryOnly -or ($Controller -and $ControllerScene) -or ($ControllerRestart -and $ControllerScene))){throw 'MultiOnly supports headless ControllerRestart or one controller mode without BoundaryOnly'}
 if($SaveId -match '[\r\n]' -or $SaveId.Contains(']==]') -or $repo.Contains(']==]')){throw 'Invalid path or save identity'}
 foreach($binary in @("$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll","$repo/build/tools/session_client.exe")) {
  if(-not (Test-Path -LiteralPath $binary)){throw "INCOMPLETE missing binary $binary"}
 }
 Get-FileHash -Algorithm SHA256 "$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll" | Format-List | Out-File "$out/binaries.log"
 Write-Lf "$out/save-id.txt" $SaveId
 Write-Lf "$out/df-path.txt" $DfPath
 if($MultiOnly){Copy-Item -LiteralPath "$PSScriptRoot/areas-multi-reference.json" -Destination "$out/multi-reference.json"}
 Enter-Df3dLane -DfPath $DfPath -Port 5010
 $entered=$true
 # Compare exact directory names across both DF save roots BEFORE creating a copy.
 # A prefix check would confuse region5 with region50 and does not prove ownership.
 if($SaveId -notmatch '^df3d-areas-[A-Za-z0-9_-]+$'){throw 'Expected a new df3d-areas-* disposable save name'}
 $saveRoots=@((Join-Path $DfPath 'save'),(Join-Path $env:APPDATA 'Bay 12 Games/Dwarf Fortress/save'))
 foreach($saveRoot in $saveRoots) {
  if(Test-Path -LiteralPath $saveRoot) {
   foreach($save in Get-ChildItem -LiteralPath $saveRoot -Directory) {
    if([string]::Equals($SaveId,$save.Name,[StringComparison]::OrdinalIgnoreCase)){throw 'Disposable name matches an existing user save'}
   }
  }
 }
 $source=Join-Path $saveRoots[0] 'region5'
 if(-not (Test-Path -LiteralPath $source -PathType Container)){throw 'INCOMPLETE source region5 missing'}
 $source=(Resolve-Path -LiteralPath $source).Path
 $clone=[IO.Path]::GetFullPath((Join-Path $saveRoots[1] $SaveId)).Replace('\','/')
 New-Item -ItemType Directory -Force -Path $saveRoots[1] | Out-Null
 Copy-Item -LiteralPath $source -Destination $clone -Recurse
 foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse) {
  $relative=$file.FullName.Substring($source.Length).TrimStart('\','/')
  if((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $clone $relative)).Hash){throw 'Disposable copy verification failed'}
 }
 foreach($savePath in @($source,$clone)) {$saveManifests[$savePath]=Save-Manifest $savePath}
 Write-Lf "$out/source-manifest.txt" $saveManifests[$source]
 Write-Lf "$out/clone-manifest.txt" $saveManifests[$clone]
 Write-Lf "$out/source-save-id.txt" 'region5'
 Write-Lf "$out/clone-path.txt" $clone
 # All waits, including restart, share this lane's 1,800 second deadline.

 Set-DfPrefs
 Install-DfMenuStartup -DfPath $DfPath
 $fixtureProcess=Start-Df3d -DfPath $DfPath
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'INCOMPLETE disposable clone could not be loaded'}
 $loaded=$true
 $session=& "$repo/build/tools/session_client.exe" status
 if($LASTEXITCODE -ne 0 -or -not ($session -match 'SESSION phase=3 ') -or -not ($session -match [regex]::Escape("id=$clone message="))){throw 'Loaded fortress identity does not match disposable copy'}
 $fixtureArgs=if($LocationScene){"[==[$out]==],'location'"}elseif($MultiOnly -or $PaintCountsOnly -or $StaffOnly){"[==[$out]==],'multi'"}else{"[==[$out]==]"}
 $r=Invoke-LuaFile 'areas-acceptance-fixture.lua' $fixtureArgs
 $r.Output | Set-Content "$out/fixture.log"
 $text=$r.Output -join "`n"
 if($text -notmatch 'FIXTURE_READY'){throw 'Fixture failed'}
 $env:DF3D_AREAS_ACCEPTANCE=$out
 $project="$repo/presentations/godot/project"
 $driver=if($MultiOnly -and $ControllerRestart){'areas_multi_restart_live.gd'}elseif($MultiOnly -and $ControllerScene){'areas_multi_scene_live.gd'}elseif($MultiOnly -and $Controller){'areas_multi_controller_live.gd'}elseif($MultiOnly){'areas_multi_live.gd'}elseif($BoundaryOnly){'areas_controller_scene_boundary_live.gd'}elseif($ControllerRestart -and $ControllerScene){'areas_controller_scene_restart_live.gd'}elseif($ControllerRestart){'areas_controller_restart_live.gd'}elseif($ControllerScene){'areas_controller_scene_live.gd'}elseif($Controller){'areas_controller_live.gd'}else{'areas_acceptance_live.gd'}
 $renderer=if($ControllerScene -or $LocationScene -or $StaffScene){''}else{'--headless --render-thread safe'}
 if($PaintCountsOnly){$driver='areas_paint_counts_live.gd'}
 if($LocationScene){$driver='areas_location_scene_live.gd'}
 if($StaffOnly){$driver='location_staff_edit_live.gd'}
 $g=Start-ContainedProcess -Exe $(if($env:DF3D_GODOT){$env:DF3D_GODOT}else{'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'}) -Arguments "$renderer --path `"$project`" --script res://tests/$driver --log-file `"$out/godot.log`"" -WorkingDir $project
 while(-not $g.HasExited -and (Get-Date) -lt $deadline) {
  if(Test-Path "$out/verify.txt") {
   $index=[int](Get-Content -Raw "$out/verify.txt")
   Remove-Item -LiteralPath "$out/verify.txt"
   $request=Get-Content -Raw "$out/request-$index.json" | ConvertFrom-Json
   if($request.op -eq 'reload') {
    if(($deadline-(Get-Date)).TotalSeconds -lt 660) {
     Write-Ack "$out/incomplete-$index" (@{reason='insufficient lane time remaining for a bounded restart'} | ConvertTo-Json -Compress)
     continue
    }
    # Once restart begins, the old fixture belongs to the old process only.
    $loaded=$false
    $oldFixtureProcess=$fixtureProcess
    try {
     $restart=Restart-Df3dFortress -SaveId $clone -SaveRoots $saveRoots -EvidenceDir "$out/restart-$index"
     if($restart.Status -eq 'ready') {
      $fixtureProcess=Get-Process -Id $restart.Pid
      $loaded=$true
      $r=Invoke-LuaFile 'areas-acceptance-fixture.lua' $fixtureArgs
      $fixtureText=$r.Output -join "`n"
      if($fixtureText -notmatch 'FIXTURE_READY') {
       Write-Ack "$out/failed-$index" (@{reason='Fixture failed after reload'} | ConvertTo-Json -Compress)
      } else {
       $loaded=$true
       Write-Ack "$out/ack-$index" (@{pid=$restart.Pid;epoch=[string]$restart.Epoch} | ConvertTo-Json -Compress)
      }
     } else {
      Write-Ack "$out/$($restart.Status)-$index" (@{reason=$restart.Reason} | ConvertTo-Json -Compress)
     }
    } catch { Write-Ack "$out/failed-$index" (@{reason=$_.Exception.Message} | ConvertTo-Json -Compress) }
    $oldFixtureProcess.Refresh()
    if(-not $oldFixtureProcess.HasExited){$loaded=$true}
    continue
   }
   # Both the native interface guard and area fingerprint are mandatory on refusals.
   if($request.op -eq 'guard_before' -or $request.op -eq 'guard_after') {
    $mode=if($request.op -eq 'guard_before'){'before'}else{'after'}
    $guard=Invoke-LuaFile 'command-guard-state.lua' "'$mode'"
    $marker=if($mode -eq 'before'){'GUARD_BASELINE'}else{'GUARD_NATIVE_UNCHANGED'}
    if(($guard.Output -join "`n") -notmatch $marker){throw "Guard $mode failed"}
   }
   if($request.op -eq 'status') {
    $status=Invoke-DfhackRaw -CommandArgs @('df3d','status')
    $status.Output | Add-Content "$out/status.log"
    $line=$status.Output -join "`n"
    "exit=$($status.ExitCode) command=status" | Add-Content "$out/status.log"
    if($status.ExitCode -eq 124 -and $line -notmatch 'area holding (\d+)/1024'){throw 'INCOMPLETE status wait cap hit'}
    if($line -notmatch 'area holding (\d+)/1024, (\d+) bytes'){throw 'Missing area status counters'}
    $holding=[int]$Matches[1]; $bytes=[long]$Matches[2]; $builders=@{}
    foreach($kind in 5..7) {
     if($line -notmatch "builder kind ${kind}: steps (\d+) / (\d+) last/max"){throw "Missing area builder $kind status"}
     $builders[[string]$kind]=@{last=[int]$Matches[1];max=[int]$Matches[2]}
     # This measures existing automatic builder work, not synchronous interactions.
     if([int]$Matches[2] -gt 2048){throw "Automatic builder $kind exceeded 2048 steps"}
    }
    Write-Lf "$out/status-$index.json" (@{holding=$holding;bytes=$bytes;builders=$builders} | ConvertTo-Json -Depth 6 -Compress)
   }
   $verifier=if(($StaffOnly -or $LocationScene) -and $request.op -like 'staff_edit_*'){'location-staff-edit-verify.lua'}elseif(($PaintCountsOnly -or $LocationScene) -and $request.op -like 'paint_counts_*'){'areas-paint-counts-verify.lua'}elseif($MultiOnly -and $request.op -like 'multi_*'){'areas-multi-verify.lua'}else{'areas-acceptance-verify.lua'}
   $r=Invoke-LuaFile $verifier "[==[$out]==],$index"
   if(($r.Output -join "`n") -notmatch 'SEMANTIC_(PASS|INCOMPLETE)'){throw "Native verification $index failed: $($r.Output)"}
   Write-Ack "$out/ack-$index" 'ok'
  }
  Start-Sleep -Milliseconds 100
  $g.Refresh()
 }
 if(-not $g.HasExited){throw 'INCOMPLETE lane deadline 1800 seconds hit'}
 if(-not (Test-Path "$out/result.json")){throw 'Godot exited without a result'}
 $result=Get-Content -Raw "$out/result.json" | ConvertFrom-Json
 $summary=[string]$result.status
 if($result.reasons){$summary+=' '+($result.reasons -join '; ')}
 if($g.ExitCode -ne 0 -and $summary -notmatch '^(failed|incomplete)'){throw 'Godot exit disagrees with result'}
 $diagnosticCode=@'
import json,sys
from pathlib import Path
sys.path.insert(0,str(Path(sys.argv[1])/'tools/qa'))
from diagnostics import error_summary
folder=Path(sys.argv[2])
report=error_summary((folder/'godot.log').read_text(encoding='utf-8',errors='replace'))
(folder/'diagnostics.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
'@
 $diagnosticCode | python - $repo $out
 if($LASTEXITCODE -ne 0){throw 'Godot diagnostic classification failed'}
 $diagnostics=Get-Content -Raw "$out/diagnostics.json" | ConvertFrom-Json
 if($diagnostics.unclassified.Count){throw 'Unexpected Godot diagnostics; see diagnostics.json'}
 if($diagnostics.known_engine.Count -and $summary -eq 'passed'){$summary='passed_with_known_issues'}
} catch {
 Write-Lf "$out/failure.txt" ($_.Exception.ToString()+"`n"+$_.ScriptStackTrace)
 $message=$_.Exception.Message
 $summary=if($message.StartsWith('INCOMPLETE ')){'incomplete '+$message.Substring(11)}else{'failed '+$message}
} finally {
 try {
  if($g -and -not $g.HasExited){$g.Kill();$g.WaitForExit()}
  if($loaded -and $fixtureProcess -and -not $fixtureProcess.HasExited) {
   # On an interrupted wait, re-pause first; the separate final assertion still
   # verifies pause before module-owned teardown, including failure paths.
   $r=Invoke-LuaFile 'areas-acceptance-verify.lua' "[==[$out]==],'pause'"
   if($StaffOnly -or $LocationScene) {
    $r=Invoke-LuaFile 'location-staff-edit-verify.lua' "[==[$out]==],'cleanup'"
    if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS cleanup staff_edit_cleanup'){throw 'Staff fixture restoration failed'}
   }
   if($PaintCountsOnly -or $LocationScene) {
    $r=Invoke-LuaFile 'areas-paint-counts-verify.lua' "[==[$out]==],'cleanup'"
    if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS paint counts restored'){throw 'Paint counts restoration failed'}
   }
   $r=Invoke-LuaFile 'areas-acceptance-verify.lua' "[==[$out]==],'final'"
   $finalPaused=($r.Output -join "`n") -match 'SEMANTIC_PASS final paused'
   if(-not $finalPaused){$summary='failed final paused verification'}
  }
 } catch {
  Write-Lf "$out/teardown-failure.txt" ($_.Exception.ToString()+"`n"+$_.ScriptStackTrace)
  $message=$_.Exception.Message
  if($message.StartsWith('INCOMPLETE ')) {
   if($summary -notlike 'failed*'){$summary='incomplete '+$message.Substring(11)+'; final pause could not be verified'}
  } else {$summary='failed teardown verification: '+$message+'; prior result: '+$summary}
 }
 finally {
  try {
   if($entered) {
    try {
     # A failed/throwing final check leaves autosave disabled until Stop-Df3d
     # destroys the process. Only then does Exit-Df3dLane restore disk prefs.
     # The fixture changes memory only, so there is no deferred Lua restore.
     if($loaded -and $finalPaused) {
      $r=Invoke-LuaFile 'areas-acceptance-verify.lua' "[==[$out]==],'restore_prefs'"
      if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS restored fixture preferences'){throw 'Fixture preference restoration failed'}
     }
    } finally {try {Stop-Df3d} finally {Exit-Df3dLane}}
   }
  }
  catch {$summary='failed teardown: '+$_.Exception.Message}
  try {
   foreach($savePath in $saveManifests.Keys) {
    if((Save-Manifest $savePath) -cne $saveManifests[$savePath]) {throw "Save changed: $savePath"}
   }
   Write-Lf "$out/save-preservation.txt" "Verified unchanged manifests for $($saveManifests.Count) save directories.`n"
  } catch {$summary='failed save preservation: '+$_.Exception.Message}
  $env:DF3D_AREAS_ACCEPTANCE=$oldInput
  Write-Lf "$out/summary.txt" ($summary+"`n")
  Write-Host "$summary -- $out"
 }
}
if($summary -like 'failed*'){exit 1}
if($summary -like 'incomplete*'){exit 77}
