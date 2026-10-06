# Protected, owned, never-saved acceptance. SaveId names a NEW disposable copy
# of region5; existing saves are refused. The copy is retained for inspection.
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SaveId,[switch]$GuardProbe,[switch]$Controller,[switch]$ControllerScene,[string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}),
 [ValidateSet('restart','inprocess')][string]$Route='restart', [string]$OwnedSaveManifest='')
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
$out="$repo/build/construction-acceptance-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
$summary='failed startup'; $entered=$false; $loaded=$false; $g=$null
$finalPaused=$false
$oldInput=$env:DF3D_CONSTRUCTION_ACCEPTANCE
$deadline=(Get-Date).AddSeconds(2400)
$sourceProof=$null
function Source-Manifest([string]$Root) {
 return (@(Get-ChildItem -LiteralPath $Root -Recurse -File | ForEach-Object {
  $_.FullName.Substring($Root.Length).TrimStart('\','/')+' '+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
 } | Sort-Object) -join "`n")
}
function Write-Lf([string]$Path,[string]$Text) {
 [IO.File]::WriteAllText($Path,($Text -replace "`r`n","`n"),[Text.UTF8Encoding]::new($false))
}
function Write-Ack([string]$Path,[string]$Text) {
 Write-Lf "$Path.tmp" $Text
 Move-Item -LiteralPath "$Path.tmp" -Destination $Path
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
 if($SaveId -notmatch '^[A-Za-z0-9_-]+$'){throw 'Expected an exact save directory name'}
 $saveRoots=@((Join-Path $DfPath 'save'),(Join-Path $env:APPDATA 'Bay 12 Games/Dwarf Fortress/save'))
 if($OwnedSaveManifest) {
  $clone=[IO.Path]::GetFullPath((Join-Path $saveRoots[1] $SaveId)).Replace('\','/')
  $sourceProof=(Get-Content -LiteralPath $OwnedSaveManifest -Raw).TrimEnd("`r","`n")
  if((Source-Manifest $clone) -cne $sourceProof){throw 'Owned save differs from its verified SHA256 manifest'}
  $original=Join-Path $saveRoots[0] 'region5'
  $matchesOriginal=(Test-Path -LiteralPath $original -PathType Container) -and ((Source-Manifest $original) -ceq $sourceProof)
  Write-Lf "$out/source-save-id.txt" $(if($matchesOriginal){'region5'}else{$SaveId})
  Write-Lf "$out/source-provenance.txt" $(if($matchesOriginal){'Owned clone matches every region5 file by SHA256.'}else{'Owned save verified; exact region5 provenance not established.'})
 } else {
 if($SaveId -notmatch '^df3d-construction-[A-Za-z0-9_-]+$'){throw 'Expected a new df3d-construction-* disposable save name'}
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
 Write-Lf "$out/source-save-id.txt" 'region5'
 $sourceProof=Source-Manifest $clone
 }
 Write-Lf "$out/source-manifest.txt" $sourceProof
 Write-Lf "$out/clone-path.txt" $clone
 # All polling and native job waits share the 2,400 second lane deadline.

 if((Get-Date) -ge $deadline){throw 'INCOMPLETE lane deadline 2400 seconds hit during setup'}
 Set-DfPrefs
 Install-DfMenuStartup -DfPath $DfPath
 $fixtureProcess=Start-Df3d -DfPath $DfPath
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'INCOMPLETE disposable clone could not be loaded'}
 $loaded=$true
 $session=& "$repo/build/tools/session_client.exe" status
 if($LASTEXITCODE -ne 0 -or -not ($session -match 'SESSION phase=3 ') -or -not ($session -match [regex]::Escape("id=$clone message="))){throw 'Loaded fortress identity does not match disposable copy'}
 $r=Invoke-LuaFile 'construction-acceptance-fixture.lua' "[==[$out]==]"
 $r.Output | Set-Content "$out/fixture.log"
 $text=$r.Output -join "`n"
 if($text -notmatch 'FIXTURE_READY'){throw 'Fixture failed'}
 Write-Lf "$out/repo.txt" $repo
 if($GuardProbe -and (Get-Content -Raw "$out/fixture.json" | ConvertFrom-Json).origin) {
  foreach($mode in @('before','after')) {
   $r=Invoke-LuaFile 'command-guard-state.lua' "'$mode'"
   $marker=if($mode -eq 'before'){'GUARD_BASELINE'}else{'GUARD_NATIVE_UNCHANGED'}
   if(($r.Output -join "`n") -notmatch $marker){throw "Guard probe $mode failed"}
  }
 }
 $env:DF3D_CONSTRUCTION_ACCEPTANCE=$out
 $project="$repo/presentations/godot/project"
 # Leave five minutes for re-pause, final readback, and result publication.
 Write-Lf "$out/budget-ms.txt" ([string][Math]::Max(0,[Math]::Floor(($deadline-(Get-Date)).TotalMilliseconds)-300000))
 $script=if($ControllerScene){'construction_controller_scene_live.gd'}elseif($Controller){'construction_controller_live.gd'}else{'construction_acceptance_live.gd'}
 $renderer=if($ControllerScene){''}else{'--headless'}
 Write-Lf "$out/controller-mode.txt" $script
 $g=Start-ContainedProcess -Exe $(if($env:DF3D_GODOT){$env:DF3D_GODOT}else{'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'}) -Arguments "$renderer --path `"$project`" --script res://tests/$script --log-file `"$out/godot.log`"" -WorkingDir $project
 while(-not $g.HasExited -and (Get-Date) -lt $deadline) {
  if(Test-Path "$out/verify.txt") {
   $index=[int](Get-Content -Raw "$out/verify.txt")
   Remove-Item -LiteralPath "$out/verify.txt"
   $request=Get-Content -Raw "$out/request-$index.json" | ConvertFrom-Json
   if($request.op -eq 'reload') {
    # Once restart begins, the old fixture belongs to the old process only.
    $loaded=$false
    $oldFixtureProcess=$fixtureProcess
    try {
     $restart=Restart-Df3dFortress -Route $Route -SaveId $clone -SaveRoots @($clone) -EvidenceDir "$out/restart-$index"
     if($restart.Status -eq 'ready') {
      $fixtureProcess=Get-Process -Id $restart.Pid
      $r=Invoke-LuaFile 'construction-acceptance-fixture.lua' "[==[$out]==]"
      $fixtureText=$r.Output -join "`n"
      if($fixtureText -match 'FIXTURE_INCOMPLETE (.+)') {
       Write-Ack "$out/incomplete-$index" (@{reason=$Matches[1]} | ConvertTo-Json -Compress)
      } elseif($fixtureText -notmatch 'FIXTURE_READY') {
       Write-Ack "$out/failed-$index" (@{reason='Fixture failed after reload'} | ConvertTo-Json -Compress)
      } else {
       $loaded=$true
       Write-Ack "$out/ack-$index" (@{pid=$restart.Pid;epoch=[string]$restart.Epoch;route=$restart.Route} | ConvertTo-Json -Compress)
      }
     } else {
      Write-Ack "$out/$($restart.Status)-$index" (@{reason=$restart.Reason} | ConvertTo-Json -Compress)
     }
    } catch { Write-Ack "$out/failed-$index" (@{reason=$_.Exception.Message} | ConvertTo-Json -Compress) }
    $oldFixtureProcess.Refresh()
    if(-not $oldFixtureProcess.HasExited){$loaded=$true}
    continue
   }
   # Refusal guards are mandatory; only Godot sends construction commands.
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
    if($status.ExitCode -eq 124){throw 'INCOMPLETE status wait cap hit'}
    if($line -notmatch 'builder kind 3: steps (\d+) / (\d+) last/max'){throw 'Missing construction builder slot'}
    if([int]$Matches[1] -gt 2048 -or [int]$Matches[2] -gt 2048){throw 'Step 2 construction builder budget exceeded'}
    if($line -notmatch 'builder steps: (\d+)'){throw 'Missing shared builder step counter'}
    if([int]$Matches[1] -gt 2048){throw 'Step 2 shared builder budget exceeded'}
    if($line -notmatch 'construction holding: none'){throw 'Unexpected construction holding state'}
   }
   $r=Invoke-LuaFile 'construction-acceptance-verify.lua' "[==[$out]==],$index"
   if(($r.Output -join "`n") -notmatch 'SEMANTIC_(PASS|INCOMPLETE)'){throw "Native verification $index failed: $($r.Output)"}
   Write-Ack "$out/ack-$index" 'ok'
  }
  Start-Sleep -Milliseconds 100
  $g.Refresh()
 }
 if(-not $g.HasExited){throw 'INCOMPLETE lane deadline 2400 seconds hit'}
 if(-not (Test-Path "$out/result.json")){throw 'Godot exited without a result'}
 $result=Get-Content -Raw "$out/result.json" | ConvertFrom-Json
 $summary=[string]$result.status
 if($result.reasons){$summary+=' '+($result.reasons -join '; ')}
 if($g.ExitCode -ne 0 -and $summary -notmatch '^(failed|incomplete)'){throw 'Godot exit disagrees with result'}
 # Assertions alone do not establish GPU acceptance. Preserve the semantic
 # result and record engine diagnostics separately using the QA classifier.
 if($ControllerScene) {
  $diagnosticCode=@'
import json, sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / 'tools' / 'qa'))
from diagnostics import error_summary
out = Path(sys.argv[2])
result = error_summary((out / 'godot.log').read_text(encoding='utf-8', errors='replace'))
(out / 'diagnostics.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
'@
  & python -c $diagnosticCode $repo $out
  if($LASTEXITCODE -ne 0){throw 'INCOMPLETE engine log classification failed'}
  $diagnostics=Get-Content -Raw "$out/diagnostics.json" | ConvertFrom-Json
  if(@($diagnostics.unclassified).Count -gt 0){$summary='failed unclassified engine diagnostics; semantic result: '+$summary}
  elseif(@($diagnostics.known_engine).Count -gt 0 -and $summary -eq 'passed'){$summary='passed_with_known_issues documented engine diagnostics'}
 }
} catch {
 $message=$_.Exception.Message
 $summary=if($message.StartsWith('INCOMPLETE ')){'incomplete '+$message.Substring(11)}else{'failed '+$message}
} finally {
 try {
  if($g -and -not $g.HasExited){$g.Kill();$g.WaitForExit()}
  if($loaded -and $fixtureProcess -and -not $fixtureProcess.HasExited) {
   # On an interrupted wait, re-pause first; the separate final assertion still
   # verifies pause before module-owned teardown, including failure paths.
   $r=Invoke-LuaFile 'construction-acceptance-verify.lua' "[==[$out]==],'pause'"
   $r=Invoke-LuaFile 'construction-acceptance-verify.lua' "[==[$out]==],'final'"
   $finalPaused=($r.Output -join "`n") -match 'SEMANTIC_PASS final paused'
   if(-not $finalPaused){$summary='failed final paused verification; prior result: '+$summary}
  }
 } catch {
  $message=$_.Exception.Message
  if($message.StartsWith('INCOMPLETE ')) {
   if($summary -like 'failed*'){$summary+='; '+$message+'; final pause could not be verified'}
   else {$summary='incomplete '+$message.Substring(11)+'; final pause could not be verified; prior result: '+$summary}
  } else {$summary='failed teardown verification: '+$message+'; prior result: '+$summary}
 }
 finally {
  try {
   if($entered) {
    try {
     # Leave autosave disabled on failed final checks until Stop-Df3d;
     # Exit-Df3dLane restores disk preferences after the process stops.
     if($loaded -and $finalPaused) {
      $r=Invoke-LuaFile 'construction-acceptance-verify.lua' "[==[$out]==],'restore_prefs'"
      if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS restored fixture preferences'){throw 'Fixture preference restoration failed'}
     }
    } finally {try {Stop-Df3d} finally {Exit-Df3dLane}}
   }
  }
  catch {$summary='failed teardown: '+$_.Exception.Message+'; prior result: '+$summary}
  try {
   if($null -ne $sourceProof) {
    if((Source-Manifest $clone) -cne $sourceProof){throw 'Owned source files changed'}
    Write-Lf "$out/save-preservation.txt" 'Owned source files unchanged.'
   }
  } catch {$summary='failed preservation: '+$_.Exception.Message}
  $env:DF3D_CONSTRUCTION_ACCEPTANCE=$oldInput
  # Evidence is read at run time. Informational comparisons never change status.
  $departures=@()
  foreach($n in 1..9) {
   $comparison="D${n}: incomplete: evidence missing"
   if(Test-Path "$out/departures.json") {
    $rows=Get-Content -Raw "$out/departures.json" | ConvertFrom-Json
    $row=$rows | Where-Object { $_.id -eq "D$n" }
    if($row){$comparison=$row.text}
   }
   $departures+=$comparison
  }
  if(Test-Path "$out/departures.json") {
   $departures+=@($rows | Where-Object { $_.id -notmatch '^D[1-9]$' } | ForEach-Object { $_.text })
  }
  Write-Lf "$out/summary.txt" ($summary+"`n"+($departures -join "`n")+"`n")
  Write-Host "$summary -- $out"
 }
}
if($summary -like 'failed*'){exit 1}
if($summary -like 'incomplete*'){exit 77}
