# Protected, owned, never-saved acceptance. SaveId names a NEW disposable copy
# of region5; existing saves are refused. The copy is retained for inspection.
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SaveId,[string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}),
 [ValidateSet('restart','inprocess')][string]$Route='restart', [string]$OwnedSaveManifest='')
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
$out="$repo/build/work-orders-acceptance-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
$summary='failed startup'; $entered=$false; $loaded=$false; $finalPaused=$false; $g=$null
$oldInput=$env:DF3D_WORK_ORDERS_ACCEPTANCE
$deadline=(Get-Date).AddSeconds(7200)
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
  # The native catalog oracle was captured from region5. Establish that exact
  # provenance from file contents, never by relabelling a related timeline.
  $original=Join-Path $saveRoots[0] 'region5'
  $matchesOriginal=(Test-Path -LiteralPath $original -PathType Container) -and ((Source-Manifest $original) -ceq $sourceProof)
  Write-Lf "$out/source-save-id.txt" $(if($matchesOriginal){'region5'}else{$SaveId})
  Write-Lf "$out/source-provenance.txt" $(if($matchesOriginal){'Owned clone matches every region5 file by SHA256.'}else{'Owned save verified; exact region5 provenance not established.'})
 } else {
 if($SaveId -notmatch '^df3d-work-orders-[A-Za-z0-9_-]+$'){throw 'Expected a new df3d-work-orders-* disposable save name'}
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
 # 2,100 s native waits + bounded paging/handshakes fit inside the 7,200 s lane cap.

 Set-DfPrefs
 Install-DfMenuStartup -DfPath $DfPath
 $fixtureProcess=Start-Df3d -DfPath $DfPath
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'INCOMPLETE disposable clone could not be loaded'}
 $loaded=$true
 $session=& "$repo/build/tools/session_client.exe" status
 if($LASTEXITCODE -ne 0 -or -not ($session -match 'SESSION phase=3 ') -or -not ($session -match [regex]::Escape("id=$clone message="))){throw 'Loaded fortress identity does not match disposable copy'}
 $r=Invoke-LuaFile 'work-orders-acceptance-fixture.lua' "[==[$out]==]"
 $r.Output | Set-Content "$out/fixture.log"
 $text=$r.Output -join "`n"
 if($text -match 'FIXTURE_INCOMPLETE (.+)'){throw "INCOMPLETE $($Matches[1])"}
 if($text -notmatch 'FIXTURE_READY'){throw 'Fixture failed'}
 $env:DF3D_WORK_ORDERS_ACCEPTANCE=$out
 $project="$repo/presentations/godot/project"
 $g=Start-ContainedProcess -Exe $(if($env:DF3D_GODOT){$env:DF3D_GODOT}else{'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'}) -Arguments "--headless --path `"$project`" --script res://tests/work_orders_acceptance_live.gd --log-file `"$out/godot.log`"" -WorkingDir $project
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
      $r=Invoke-LuaFile 'work-orders-acceptance-fixture.lua' "[==[$out]==]"
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
   # Step 6/10 guards are mandatory. No second client sends work-order commands.
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
    if($status.ExitCode -eq 124 -and $line -notmatch 'work-order holding: (\d+)/4096; builder steps: (\d+)'){throw 'INCOMPLETE status wait cap hit'}
    if($line -notmatch 'work-order holding: (\d+)/4096; builder steps: (\d+)'){throw 'Missing work-order status counters'}
    $holding=[int]$Matches[1]; $steps=[int]$Matches[2]
    if($steps -gt 2048){throw "Step 2 builder budget exceeded: $steps"}
    Write-Lf "$out/status-$index.json" (@{holding=$holding;steps=$steps} | ConvertTo-Json -Compress)
   }
   $r=Invoke-LuaFile 'work-orders-acceptance-verify.lua' "[==[$out]==],$index"
   if(($r.Output -join "`n") -notmatch 'SEMANTIC_(PASS|INCOMPLETE)'){throw "Native verification $index failed: $($r.Output)"}
   Write-Ack "$out/ack-$index" 'ok'
  }
  Start-Sleep -Milliseconds 100
  $g.Refresh()
 }
 if(-not $g.HasExited){throw 'INCOMPLETE lane deadline 7200 seconds hit'}
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
  if($loaded -and $fixtureProcess -and -not $fixtureProcess.HasExited) {
   # On an interrupted wait, re-pause first; the separate final assertion still
   # verifies pause before module-owned teardown, including failure paths.
   $r=Invoke-LuaFile 'work-orders-acceptance-verify.lua' "[==[$out]==],'pause'"
   $r=Invoke-LuaFile 'work-orders-acceptance-verify.lua' "[==[$out]==],'final'"
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
     # A failed/throwing final check leaves autosave disabled until Stop-Df3d
     # destroys the process. Only then does Exit-Df3dLane restore disk prefs.
     # The fixture changes memory only, so there is no deferred Lua restore.
     if($loaded -and $finalPaused) {
      $r=Invoke-LuaFile 'work-orders-acceptance-verify.lua' "[==[$out]==],'restore_prefs'"
      if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS restored fixture preferences'){throw 'Fixture preference restoration failed'}
     }
    } finally {try {Stop-Df3d} finally {Exit-Df3dLane}}
   }
  }
  catch {$summary='failed teardown: '+$_.Exception.Message}
  try {
   if($null -ne $sourceProof) {
    if((Source-Manifest $clone) -cne $sourceProof){throw 'Owned source files changed'}
    Write-Lf "$out/save-preservation.txt" 'Owned source files unchanged.'
   }
  } catch {$summary='failed preservation: '+$_.Exception.Message}
  $env:DF3D_WORK_ORDERS_ACCEPTANCE=$oldInput
  Write-Lf "$out/summary.txt" ($summary+"`n")
  Write-Host "$summary -- $out"
 }
}
if($summary -like 'failed*'){exit 1}
if($summary -like 'incomplete*'){exit 77}
