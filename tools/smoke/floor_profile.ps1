# Maintainer reference probe: targets a specific development fort/unit; not part of the supported workflow.
# Testfort renderer benchmark: hidden owned DF/Godot, no saves.
# Most cases stay paused; mesh_batch_motion_live briefly runs then restores pause. Preserves the user's presentation settings.
param(
 [Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SaveId,
 [string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}),
 [ValidateSet('floor_profile_live','mesh_batch_profile_live','mesh_batch_motion_live','visibility_profile_live','frame_breakdown_live','profiling_scene_test','render_quality_live','ui_availability_live','read_only_info_live','resident_roster_live','world_markers_live','context_inspect_live','creature_sheet_live','item_culling_profile_live','render_attribution_live','deep_profile_live','building_residency_live','gameplay_demo_live','targeted_attack_live')][string]$Test='floor_profile_live',
 [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$OutputName='testfort-floor-perf',
 [ValidateSet('project','safe','separate')][string]$RenderThread='project',
 [Alias('Profile')][ValidateSet('off','basic','deep')][string]$Profiling='basic',
 [int]$TimeoutSec=1200,
 [switch]$ItemProbe,
 [switch]$UnitProbe,
 [switch]$SyncProbe,
 [switch]$RenderProbe,
 [switch]$SubmissionProbe,
 [switch]$Arena,
 [switch]$ArenaDiagnostics,
 [ValidateSet(1,2,4,8)][int]$ArenaScale=1,
 [ValidateRange(0,16)][int]$ArenaHeadroom=4,
 [ValidateSet('duel','gate','crossbows','dragon','monsters','unarmed','hill','platform')][string]$ArenaScenario='duel'
)
$ErrorActionPreference='Stop'
if($ArenaDiagnostics -and -not $Arena){throw 'ArenaDiagnostics requires Arena'}
if($Arena -and $Test -ne 'targeted_attack_live'){throw 'Arena requires targeted_attack_live'}
Import-Module (Join-Path $PSScriptRoot 'Df3dLane.psm1') -Force
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$cfg=Join-Path $env:APPDATA 'Godot/app_userdata/DF3D/presentation.cfg'
$prior=if(Test-Path -LiteralPath $cfg){[IO.File]::ReadAllBytes($cfg)}else{$null}
$vars=@{DF3D_HITCHES='1';DF3D_AUDIO_SILENT='1';DF3D_FLOOR_PERF_OUT="$repo/build/$OutputName";DF3D_WINDOW='24';DF3D_FIXTURE='';DF3D_SCREENSHOT='';DF3D_CAM_MODE='free';DF3D_CAM_PITCH='-0.9';DF3D_CAM_YAW='0'}
$previous=@{}
$vars['DF3D_OBS_CAPTURE']='0' # targeted_attack_live.gd reads this; the OBS capture lane was removed
$vars['DF3D_CAPTURE_HEADROOM']=[string]$ArenaHeadroom
$vars['DF3D_ARENA_DIAGNOSTICS']=if($ArenaDiagnostics){'1'}else{'0'}
$vars['DF3D_PROFILE']=$Profiling
$vars['DF3D_UNIT_PROBE']=if($UnitProbe){'1'}else{'0'}
if($UnitProbe -and $Profiling -ne 'deep'){throw 'UnitProbe requires deep profiling'}
$vars['DF3D_ITEM_PROBE']=if($ItemProbe){'1'}else{'0'}
if($ItemProbe -and $Profiling -ne 'deep'){throw 'ItemProbe requires deep profiling'}
$vars['DF3D_SYNC_PROBE']=if($SyncProbe){'1'}else{'0'}
if($SyncProbe -and $Profiling -ne 'deep'){throw 'SyncProbe requires deep profiling'}
$vars['DF3D_RENDER_PROBE']=if($RenderProbe){'1'}else{'0'}
if($RenderProbe -and ($Profiling -ne 'deep' -or $Test -notin @('deep_profile_live','render_attribution_live','item_culling_profile_live'))){throw 'RenderProbe requires deep_profile_live or render_attribution_live with deep profiling'}
$vars['DF3D_SUBMISSION_DETAIL']=if($SubmissionProbe){'1'}else{'0'}
if($SubmissionProbe -and ($Profiling -ne 'deep' -or $Test -ne 'deep_profile_live')){throw 'SubmissionProbe requires deep_profile_live with deep profiling'}
$vars['DF3D_PROFILE_OUT']="$repo/build/$OutputName"
$vars['DF3D_PERF_NO_RENDER_READBACK']='1'
try {
 Enter-Df3dLane -DfPath $dfPath -Port 5010
 foreach($key in $vars.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$vars[$key],'Process')}
 Set-DfPrefs
 Install-DfMenuStartup -DfPath $dfPath
 $d=Start-Df3d -DfPath $dfPath
 if($Arena -and $ArenaScenario -eq 'monsters'){
  # Development-only native arena. Official installed packs, no saved-world edits.
  $luaRepo=$repo.Replace('\','/')
  $bootstrapStatus="$repo/build/$OutputName-bootstrap.json"
  if(Test-Path -LiteralPath $bootstrapStatus){Remove-Item -LiteralPath $bootstrapStatus}
  $bootstrap="assert(loadfile('$luaRepo/tools/smoke/arena_bootstrap_start.lua'))('$luaRepo/build/$OutputName-bootstrap.json')"
  $deadline=(Get-Date).AddSeconds(80)
  do {
   $result=Invoke-DfhackRaw -CommandArgs @('lua',$bootstrap) -TimeoutSec 5
   if(($result.Output -join "`n") -match 'ARENA_BOOTSTRAP_STARTED'){break}
   Start-Sleep -Milliseconds 500
  } while((Get-Date) -lt $deadline)
  if(($result.Output -join "`n") -notmatch 'ARENA_BOOTSTRAP_STARTED'){throw 'Arena bootstrap did not start'}
  $ready=$false
  while((Get-Date) -lt $deadline){
   if(Test-Path -LiteralPath $bootstrapStatus){
    # Lua replaces a tiny status file; retry a read that overlaps its write.
    try {$status=Get-Content -LiteralPath $bootstrapStatus -Raw | ConvertFrom-Json} catch {$status=$null}
    if($status.error){throw $status.error}
    if($status.ready){$ready=$true;break}
   }
   Start-Sleep -Milliseconds 200
  }
  if(-not $ready){throw 'Native arena bootstrap timed out'}
 }else{
  & "$repo/build/tools/session_client.exe" load $SaveId *> "$repo/build/$OutputName-native-load.log"
  if($LASTEXITCODE -ne 0){throw 'Native load failed'}
 }
 if($Test -eq 'creature_sheet_live'){
  $luaRepo=$repo.Replace('\','/')
  $scar=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile('$luaRepo/tools/smoke/portrait-scar-test.lua'))(86)") -TimeoutSec 120
  $scar.Output | Set-Content "$repo/build/$OutputName-scar-test.log"
  if($scar.ExitCode -ne 0 -or ($scar.Output -join "`n") -notmatch 'PORTRAIT_SCAR_TEST_PASS'){throw 'Portrait scar regression failed'}
 }
 if($Test -eq 'targeted_attack_live'){
  $luaRepo=$repo.Replace('\','/')
  $setupScript=if($Arena){'arena_demo_setup.lua'}else{'attack_demo_setup.lua'}
  $detailsArg=if($ArenaDiagnostics){",'$luaRepo/build/$OutputName-diagnostics.jsonl'"}else{',nil'}
  if($Arena){$detailsArg+=",$ArenaScale"}
  # Shared staging output must never be mistaken for evidence from a prior run.
  if(Test-Path -LiteralPath "$repo/build/targeted-attack-setup.json"){
   Remove-Item -LiteralPath "$repo/build/targeted-attack-setup.json"
  }
  $setup="assert(loadfile('$luaRepo/tools/smoke/$setupScript'))('$luaRepo/build/targeted-attack-setup.json','$ArenaScenario'$detailsArg)"
  $setupResult=Invoke-DfhackRaw -CommandArgs @('lua',$setup) -TimeoutSec 300
  $setupResult.Output | Set-Content "$repo/build/$OutputName-setup.log"
  if(($setupResult.Output -join "`n") -notmatch 'ATTACK_DEMO_SETUP'){throw 'Battle setup failed'}
 }
 $project="$repo/presentations/godot/project"
 $threadArgs=if($RenderThread -eq 'project'){''}else{"--render-thread $RenderThread "}
 $debugArgs=''
 if($RenderProbe){
  $readyPath="$repo/build/$OutputName-render-ready.json"
  $renderPath="$repo/build/$OutputName-render.json"
  foreach($oldPath in @($readyPath,$renderPath)){if(Test-Path -LiteralPath $oldPath){Remove-Item -LiteralPath $oldPath}}
  $python=(Get-Command python -ErrorAction Stop).Source
  $collector=Start-ContainedProcess -Exe $python -Arguments "`"$repo/tools/smoke/render_profile_collector.py`" --ready `"$readyPath`" --output `"$renderPath`" --timeout $TimeoutSec" -WorkingDir $repo
  $collectorHandle=$collector.Handle
  $readyDeadline=(Get-Date).AddSeconds(15)
  while(-not (Test-Path -LiteralPath $readyPath) -and (Get-Date) -lt $readyDeadline){
   if($collector.HasExited){throw 'Render collector exited before listening'}
   Start-Sleep -Milliseconds 100
  }
  if(-not (Test-Path -LiteralPath $readyPath)){throw 'Render collector did not become ready'}
  $port=(Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json).port
  $debugArgs="--remote-debug tcp://127.0.0.1:$port --ignore-error-breaks "
 }
 $g=Start-ContainedProcess -Exe $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' }) -Arguments "${threadArgs}${debugArgs}--path `"$project`" --script res://tests/$Test.gd --log-file `"$repo/build/$OutputName.log`"" -WorkingDir $project
 # Hold the process handle before exit so Get-Process can report ExitCode.
 $heldHandle=$g.Handle
 $deadline=(Get-Date).AddSeconds($TimeoutSec)
 while((Get-Date) -lt $deadline){if($g.WaitForExit(15000)){break}}
 if(-not $g.HasExited){throw 'Floor benchmark timed out'}
 (Invoke-DfhackRaw -CommandArgs @('df3d','status')).Output | Set-Content "$repo/build/$OutputName-native-status.log"
 $g.ExitCode | Set-Content "$repo/build/$OutputName-exit.txt"
 $log=Get-Content "$repo/build/$OutputName.log" -Raw
 # Each script prints its own marker (<TEST>_PASS), so a log from another test cannot pass this one.
 $marker=if($Test -eq 'profiling_scene_test'){'PROFILING_SCENE_PASS'}else{$Test.ToUpperInvariant()+'_PASS'}
 if($g.ExitCode -ne 0 -or $log -notmatch ('(?m)^'+[regex]::Escape($marker)) -or $log -match '(?m)SCRIPT ERROR|^ERROR:'){throw "Benchmark failed: $OutputName.log (expected $marker)"}
 if($Test -eq 'targeted_attack_live'){
  if($Arena){
   $flush=Invoke-DfhackRaw -CommandArgs @('lua', 'assert(df3d_arena_capture_flush)(); print("ARENA_CAPTURE_FLUSHED")')
   if(($flush.Output -join "`n") -notmatch 'ARENA_CAPTURE_FLUSHED'){throw 'Arena diagnostics flush failed'}
  }
  $native=Get-Content "$repo/build/targeted-attack-setup.json" -Raw | ConvertFrom-Json
  if ($native.error) { throw "targeted-attack setup reported an error: $($native.error)" }
  Copy-Item -LiteralPath "$repo/build/targeted-attack-setup.json" -Destination "$repo/build/$OutputName-native-actions.json" -Force
  $render=Get-Content "$repo/build/$OutputName.json" -Raw | ConvertFrom-Json
  $nativeKeys=@{}
  foreach($action in $native.actions){$nativeKeys["$($action.attacker):$($action.action)"]=$true}
  foreach($action in $render.observations){
   if(-not $nativeKeys.ContainsKey("$($action.unit):$($action.action)")){throw 'Rendered attack lacks independent native observation'}
  }
  if(@($render.observations | Where-Object {$_.unit -in $native.units}).Count -eq 0 -and @($render.combat_events).Count -eq 0 -and @($render.projectile_releases).Count -eq 0){throw 'Staged combatants never fought'}
  if($Arena){
   if(@($render.combat_events).Count -eq 0){throw 'Arena lacks confirmed combat outcomes'}
   if($ArenaScenario -eq 'crossbows'){
    if(@($native.projectiles).Count -eq 0 -or @($render.projectile_releases).Count -eq 0 -or $render.projectile_peak -lt 1 -or @($render.shot_reactions).Count -eq 0){throw 'Crossbow capture lacks actual visible flight and recoil'}
    $nativeProjectiles=@{}; foreach($projectile in $native.projectiles){$nativeProjectiles[[string]$projectile.id]=$true}
    if(@($render.projectiles_seen | Where-Object {$nativeProjectiles.ContainsKey([string]$_)}).Count -eq 0){throw 'No visible projectile matches an independently observed arena shot'}
   }
   foreach($event in $render.combat_events){
    if($event.kind -ne 2){continue}
    $victim=@($native.combatants | Where-Object {$_.id -eq $event.victim_id})
    if($victim.Count -ne 1 -or -not $victim[0].latest.dead){throw 'Rendered death lacks native death confirmation'}
   }
  }
 }
 if($RenderProbe){
  if(-not $collector.WaitForExit(20000)){throw 'Render collector did not finish after Godot exit'}
  if($collector.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $renderPath)){throw 'Render collector failed'}
 }
 $resultSuffix=if($Test -eq 'profiling_scene_test'){'.profile.json'}else{'.json'}
 Write-Output "Benchmark PASS: build/$OutputName$resultSuffix"
} finally {
 # Flush evidence before closing even when capture/validation failed.
 if($ArenaDiagnostics -and $null -ne $d){
  try {
   $finish=Invoke-DfhackRaw -CommandArgs @('lua','if df3d_arena_capture_finish then df3d_arena_capture_finish() end') -TimeoutSec 10
   $finish.Output | Set-Content "$repo/build/$OutputName-diagnostics-finish.log"
   if(Test-Path -LiteralPath "$repo/build/targeted-attack-setup.json"){
    Copy-Item -LiteralPath "$repo/build/targeted-attack-setup.json" -Destination "$repo/build/$OutputName-native-actions.json" -Force
   }
  }catch{Write-Warning "Could not finalize encounter evidence: $_"}
 }
 Exit-Df3dLane
 foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
 if($null -ne $prior){[IO.File]::WriteAllBytes($cfg,$prior)}
}
