# Protected, owned, never-saved acceptance. SaveId names a NEW disposable copy
# of region5; existing saves are refused. The copy is retained for inspection.
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SaveId,[switch]$GuardProbe,[string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}))
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
$out="$repo/build/work-details-acceptance-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
$summary='failed startup'; $entered=$false; $loaded=$false; $finalPaused=$false; $g=$null
$oldInput=$env:DF3D_WORK_DETAILS_ACCEPTANCE
$deadline=(Get-Date).AddSeconds(1800)
function Write-Lf([string]$Path,[string]$Text) {
 [IO.File]::WriteAllText($Path,($Text -replace "`r`n","`n"),[Text.UTF8Encoding]::new($false))
}
function Invoke-LuaFile([string]$Name,[string]$Arguments) {
 # Lua long strings prevent paths/SaveId from becoming executable Lua text.
 $r=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile([==[$repo/tools/smoke/$Name]==]))($Arguments)")
 $r.Output | Add-Content "$out/native.log"
 "exit=$($r.ExitCode) script=$Name" | Add-Content "$out/native.log"
 if($r.ExitCode -eq 124){throw 'INCOMPLETE DFHack wait cap hit; outcome unknown, no replay'}
 # dfhack-run can AV at exit after success; callers judge server markers.
 return $r
}
try {
 if($SaveId -match '[\r\n]' -or $SaveId.Contains(']==]') -or $repo.Contains(']==]')){throw 'Invalid path or save identity'}
 foreach($binary in @("$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll","$repo/build/tools/session_client.exe")) {
  if(-not (Test-Path -LiteralPath $binary)){throw "INCOMPLETE missing binary $binary"}
 }
 Get-FileHash -Algorithm SHA256 "$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll" | Format-List | Out-File "$out/binaries.log"
 Write-Lf "$out/save-id.txt" $SaveId
 Enter-Df3dLane -DfPath $DfPath -Port 5010
 $entered=$true
 # Compare exact directory names across both DF save roots BEFORE creating a copy.
 # A prefix check would confuse region5 with region50 and does not prove ownership.
 if($SaveId -notmatch '^df3d-work-details-[A-Za-z0-9_-]+$'){throw 'Expected a new df3d-work-details-* disposable save name'}
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
 Write-Lf "$out/source-save-id.txt" 'region5'
 Write-Lf "$out/clone-path.txt" $clone
 # The outer deadline bounds the complete acceptance session.

 Set-DfPrefs
 Install-DfMenuStartup -DfPath $DfPath
 Start-Df3d -DfPath $DfPath | Out-Null
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'INCOMPLETE disposable clone could not be loaded'}
 $loaded=$true
 $session=& "$repo/build/tools/session_client.exe" status
 if($LASTEXITCODE -ne 0 -or -not ($session -match 'SESSION phase=3 ') -or -not ($session -match [regex]::Escape("id=$clone message="))){throw 'Loaded fortress identity does not match disposable copy'}
 $r=Invoke-LuaFile 'work-details-acceptance-fixture.lua' "[==[$out]==]"
 $r.Output | Set-Content "$out/fixture.log"
 $text=$r.Output -join "`n"
 if($text -notmatch 'FIXTURE_READY'){throw 'Fixture failed'}
 if($GuardProbe -and (Get-Content -Raw "$out/fixture.json" | ConvertFrom-Json).guard_available) {
  foreach($mode in @('before','after')) {
   $probe=Invoke-LuaFile 'command-guard-state.lua' "'$mode'"
   $marker=if($mode -eq 'before'){'GUARD_BASELINE'}else{'GUARD_NATIVE_UNCHANGED'}
   if(($probe.Output -join "`n") -notmatch $marker){throw "Guard probe $mode failed"}
  }
 }
 # HEAD exports no reload helper. Do not improvise a save or process restart.
 Write-Lf "$out/reload.txt" 'incomplete step 9: Df3dLane exports no reload helper'
 Write-Lf "$out/capture-questions.txt" "What does DF's Labor widget show if a detail is deleted while the native Work Details tab is open?`n"
 $departures=@()
 $evidence="$repo/build/evidence/native/e6/findings.md"
 $findings=if(Test-Path -LiteralPath $evidence){Get-Content -LiteralPath $evidence}else{@()}
 # D1, D5 and D6 cite findings; D7 derives from the initial detail dump.
 $items=@(1,0,0,0,4,5,0)
 for($i=0;$i -lt 7;$i++) {
  $n=$items[$i];$lines=@();$capture=$false
  foreach($line in $findings) {
   if($line -match '^\d+\. '){$capture=$n -gt 0 -and $line -match "^$n\. "}
   elseif([string]::IsNullOrWhiteSpace($line)){$capture=$false}
   if($capture){$lines+=$line.Trim()}
  }
  $record=if($lines.Count){"F${n}: $($lines -join ' ')"}else{'incomplete: evidence missing'}
  if($i -eq 6) {
   $initial="$repo/build/evidence/native/e6/wd_00_initial.txt"
   if(Test-Path -LiteralPath $initial) {
    $dump=Get-Content -Raw -LiteralPath $initial
    if($dump -match '(?m)^\[\d+\].*icon=' -and $dump -notmatch 'icon=SIEGE_OPERATORS(?:\s|$)') {
     $record='wd_00_initial.txt: no SIEGE_OPERATORS entry'
    }
   }
  }
  $departures+="D$($i+1): $record"
 }
 Write-Lf "$out/departures.txt" ($departures -join "`n")
 $env:DF3D_WORK_DETAILS_ACCEPTANCE=$out
 $project="$repo/presentations/godot/project"
 # Reserve teardown time inside the 1,800-second wall cap.
 Write-Lf "$out/budget-ms.txt" ([string][Math]::Max(0,[Math]::Floor(($deadline-(Get-Date)).TotalMilliseconds)-180000))
 $g=Start-ContainedProcess -Exe $(if($env:DF3D_GODOT){$env:DF3D_GODOT}else{'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'}) -Arguments "--headless --path `"$project`" --script res://tests/work_details_acceptance_live.gd --log-file `"$out/godot.log`"" -WorkingDir $project
 while(-not $g.HasExited -and (Get-Date) -lt $deadline) {
  if(Test-Path "$out/verify.txt") {
   $index=[int](Get-Content -Raw "$out/verify.txt")
   Remove-Item -LiteralPath "$out/verify.txt"
   $request=Get-Content -Raw "$out/request-$index.json" | ConvertFrom-Json
   # Refusal guards are mandatory, including without -GuardProbe.
   if($request.op -eq 'guard_before' -or $request.op -eq 'guard_after') {
    $mode=if($request.op -eq 'guard_before'){'before'}else{'after'}
    $guard=Invoke-LuaFile 'command-guard-state.lua' "'$mode'"
    $marker=if($mode -eq 'before'){'GUARD_BASELINE'}else{'GUARD_NATIVE_UNCHANGED'}
    if(($guard.Output -join "`n") -notmatch $marker){throw "step $($request.step): guard $mode failed"}
   }
   if($request.op -eq 'rename_out_of_band') {
    $r=Invoke-LuaFile 'work-details-acceptance-fixture.lua' "[==[$out]==],'rename',$($request.detail_index)"
    if(($r.Output -join "`n") -notmatch 'FIXTURE_RENAMED'){throw 'failed step 7: fixture rename failed'}
   }
   if($request.op -eq 'status') {
    $status=Invoke-DfhackRaw -CommandArgs @('df3d','status')
    $line=$status.Output -join "`n"
    $line | Add-Content "$out/status.log"
    if($status.ExitCode -eq 124){throw 'INCOMPLETE status wait cap hit'}
    # Parsed status counters determine success even after a client exit AV.
    if($line -notmatch 'work-detail holding (\d+)/256'){throw 'Missing work-detail holding counter'}
    $holding=[int]$Matches[1]
    if($line -notmatch 'builder kind 4: steps (\d+) / (\d+) last/max'){throw 'Missing kind 4 counters'}
    $last=[int]$Matches[1];$max=[int]$Matches[2]
    if($last -gt 2048 -or $max -gt 2048){throw 'failed step 6: kind 4 budget exceeded'}
    if($line -notmatch 'builder steps: (\d+)'){throw 'Missing shared builder steps'}
    $shared=[int]$Matches[1]
    if($shared -gt 2048){throw 'failed step 6: shared budget exceeded'}
    Write-Lf "$out/status-$index.json" (@{holding=$holding;steps=$last;max=$max;shared=$shared} | ConvertTo-Json -Compress)
   }
   $r=Invoke-LuaFile 'work-details-acceptance-verify.lua' "[==[$out]==],$index"
   if(($r.Output -join "`n") -notmatch 'SEMANTIC_(PASS|INCOMPLETE|FAIL)'){throw "Native verification $index failed: $($r.Output)"}
   Write-Lf "$out/ack-$index" 'ok'
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
} catch {
 $message=$_.Exception.Message
 $summary=if($message.StartsWith('INCOMPLETE ')){'incomplete '+$message.Substring(11)}else{'failed '+$message}
} finally {
 try {
  if($g -and -not $g.HasExited){$g.Kill();$g.WaitForExit()}
  if($loaded) {
   # On an interrupted wait, re-pause first; the separate final assertion still
   # verifies pause before module-owned teardown, including failure paths.
   $r=Invoke-LuaFile 'work-details-acceptance-verify.lua' "[==[$out]==],'pause'"
   if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS pause'){throw 'Final pause command failed'}
   $r=Invoke-LuaFile 'work-details-acceptance-verify.lua' "[==[$out]==],'final'"
   $finalPaused=($r.Output -join "`n") -match 'SEMANTIC_PASS final paused'
   if(-not $finalPaused){$summary='failed final paused verification'}
  }
 } catch {
  $message=$_.Exception.Message
  if($message.StartsWith('INCOMPLETE ')) {
   if($summary -notlike 'failed*'){$summary='incomplete '+$message.Substring(11)+'; final pause could not be verified'}
  } else {$summary='failed teardown verification: '+$message}
 }
 finally {
  try {
   if($entered) {
    try {
     # Restore memory only after final pause/autosave verification. On failure,
     # leave autosave disabled until the owned process exits; then restore disk prefs.
     if($loaded -and $finalPaused) {
      $r=Invoke-LuaFile 'work-details-acceptance-verify.lua' "[==[$out]==],'restore_prefs'"
      if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS restored fixture preferences'){throw 'Fixture preference restoration failed'}
     }
    } finally {try {Stop-Df3d} finally {Exit-Df3dLane}}
   }
  }
  catch {$summary='failed teardown: '+$_.Exception.Message}
  $env:DF3D_WORK_DETAILS_ACCEPTANCE=$oldInput
  $extra=if(Test-Path "$out/departures.txt"){Get-Content -Raw "$out/departures.txt"}else{'D1-D7: incomplete: evidence missing'}
  $question="Capture question: What does DF's Labor widget show if a detail is deleted while the native Work Details tab is open?"
  Write-Lf "$out/summary.txt" ($summary+"`nStep 10 (informational):`n"+$extra+"`n"+$question+"`nRound-robin fairness: offline only.`n")
  Write-Host "$summary -- $out"
 }
}
if($summary -like 'failed*'){exit 1}
if($summary -like 'incomplete*'){exit 77}
