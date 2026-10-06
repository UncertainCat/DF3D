# Native HUD count acceptance on an owned, never-saved clone. SaveId names a NEW disposable copy
# of region5; existing saves are refused. The copy is retained for inspection.
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SaveId,[string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}))
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
$out="$repo/build/hud-resource-acceptance-$(Get-Date -Format yyyyMMdd-HHmmss)"
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
 if($SaveId -match '[\r\n]' -or $SaveId.Contains(']==]') -or $repo.Contains(']==]')){throw 'Invalid path or save identity'}
 foreach($binary in @("$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll","$repo/build/tools/session_client.exe")) {
  if(-not (Test-Path -LiteralPath $binary)){throw "INCOMPLETE missing binary $binary"}
 }
 Get-FileHash -Algorithm SHA256 "$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll" | Format-List | Out-File "$out/binaries.log"
 Write-Lf "$out/save-id.txt" $SaveId
 Write-Lf "$out/df-path.txt" $DfPath
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
 $fixtureArgs="[==[$out]==],'multi'"
 $r=Invoke-LuaFile 'areas-acceptance-fixture.lua' $fixtureArgs
 $r.Output | Set-Content "$out/fixture.log"
 $text=$r.Output -join "`n"
 if($text -notmatch 'FIXTURE_READY'){throw 'Fixture failed'}
 $env:DF3D_AREAS_ACCEPTANCE=$out
 $project="$repo/presentations/godot/project"
 $driver='hud_resource_live.gd'
 $renderer='--headless --render-thread safe'
 $g=Start-ContainedProcess -Exe $(if($env:DF3D_GODOT){$env:DF3D_GODOT}else{'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'}) -Arguments "$renderer --path `"$project`" --script res://tests/$driver --log-file `"$out/godot.log`"" -WorkingDir $project
 while(-not $g.HasExited -and (Get-Date) -lt $deadline) {
  if(Test-Path "$out/verify.txt") {
   $index=[int](Get-Content -Raw "$out/verify.txt")
   Remove-Item -LiteralPath "$out/verify.txt"
   $request=Get-Content -Raw "$out/request-$index.json" | ConvertFrom-Json
   $verifier='hud-resource-verify.lua'
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
   $r=Invoke-LuaFile 'hud-resource-verify.lua' "[==[$out]==],'cleanup'"
   if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS hud_restore'){throw 'HUD counters/precision restoration failed'}
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
