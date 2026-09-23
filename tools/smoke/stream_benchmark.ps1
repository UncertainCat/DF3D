# Maintainer reference probe: targets a specific development fort/unit; not part of the supported workflow.
# Compare native simulation throughput and latest-publication delivery in Testfort.
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SaveId,[string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}),[string]$OutputName='testfort-stream',[int]$Seconds=25,[switch]$ReaderOnly,[switch]$ViewerOnly,[switch]$ItemProbe,[switch]$UnitProbe,[switch]$CpuBoundaries,[switch]$FrameBoundaries,[ValidateSet('off','basic','deep')][string]$Profiling='off',[ValidateSet('billboard','classic')][string]$RenderStyle='billboard',[ValidateRange(0,240)][int]$FrameCap=60)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Df3dLane.psm1') -Force
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$df=$DfPath
$prefix="$repo/build/$OutputName"
if(Test-Path "$prefix-info.json"){throw 'Choose a new output name'}
function Lua([string]$code) {
 $r=Invoke-DfhackRaw -CommandArgs @('lua',$code) -TimeoutSec 15
 if($r.ExitCode -ne 0){throw ($r.Output -join "`n")}
 return $r
}
function Control([string]$phase) {
 @{phase=$phase}|ConvertTo-Json -Compress|Set-Content "$prefix-control.json"
 $deadline=(Get-Date).AddSeconds(15)
 do {
  Start-Sleep -Milliseconds 200
  try {$ack=Get-Content "$prefix-ack.json" -Raw -ErrorAction Stop|ConvertFrom-Json}catch{$ack=$null}
  if($null -ne $ack -and $ack.phase -eq $phase){return}
 }while((Get-Date)-lt $deadline)
 throw "Godot did not acknowledge $phase"
}
function Phase([string]$name,[bool]$enabled,[bool]$viewer=$false) {
 Write-Output "PHASE_PREP $name"
 $r=Invoke-DfhackRaw -CommandArgs @($(if($enabled){'enable'}else{'disable'}),'df3d')
 if($r.ExitCode-ne 0){throw ($r.Output-join "`n")}
 Lua 'df.global.pause_state=false'|Out-Null
 Start-Sleep -Seconds 6
 if($enabled){$r=Invoke-DfhackRaw -CommandArgs @('df3d','status');$r.Output|Set-Content "$prefix-$name-before-status.log"}
 if($viewer){Control $name}
 $luaPath=$repo.Replace('\','/')+'/tools/smoke/stream_probe.lua'
 $native=($prefix+"-$name-native.json").Replace('\','/')
 Lua "assert(loadfile('$luaPath'))('start','$native','$name',$Seconds)"|Out-Null
 $deadline=(Get-Date).AddSeconds($Seconds+30)
 while(-not(Test-Path $native) -and (Get-Date)-lt $deadline){Start-Sleep -Milliseconds 250}
 if(-not(Test-Path $native)){throw "Native probe timed out $name"}
 if($viewer){Control ''}
 if($enabled){$r=Invoke-DfhackRaw -CommandArgs @('df3d','status');$r.Output|Set-Content "$prefix-$name-after-status.log"}
 $data=Get-Content $native -Raw|ConvertFrom-Json
 Write-Output "PHASE_DONE $name sim_fps=$([math]::Round($data.sim_fps,2)) ticks=$($data.end_tick-$data.start_tick)"
}
$vars=@{DF3D_HITCHES='1';DF3D_STREAM_BENCH_OUT=$prefix;DF3D_STREAM_BENCH_STYLE=$RenderStyle;DF3D_AUDIO_SILENT='1';DF3D_PROFILE=$Profiling;DF3D_PROFILE_OUT=$prefix;DF3D_HITCH_OUT="$prefix-hitches.jsonl";DF3D_FIXTURE='';DF3D_WINDOW='24';DF3D_PERF_NO_RENDER_READBACK='1';DF3D_UI_SETTINGS_PATH="$prefix-settings.cfg"}
$old=@{}
if($ItemProbe -and $Profiling -ne 'deep'){throw 'ItemProbe requires deep profiling'}
if($UnitProbe -and $Profiling -ne 'deep'){throw 'UnitProbe requires deep profiling'}
if($CpuBoundaries -and $Profiling -ne 'deep'){throw 'CpuBoundaries requires deep profiling'}
$vars['DF3D_FRAME_BOUNDARIES']=$(if($FrameBoundaries){'1'}else{'0'})
$vars['DF3D_CPU_BOUNDARIES']=$(if($CpuBoundaries){'1'}else{'0'})
$vars['DF3D_ITEM_PROBE']=$(if($ItemProbe){'1'}else{'0'})
$vars['DF3D_UNIT_PROBE']=$(if($UnitProbe){'1'}else{'0'})
$vars['DF3D_STREAM_FRAME_CAP']=[string]$FrameCap
try {
 Enter-Df3dLane -DfPath $df -Port 5010
 foreach($key in $vars.Keys){$old[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$vars[$key],'Process')}
 Set-DfPrefs
 Install-DfMenuStartup -DfPath $df
 $d=Start-Df3d -DfPath $df
 & "$repo/build/tools/session_client.exe" load $SaveId *> "$prefix-load.log"
 if($LASTEXITCODE-ne 0){throw 'Save load failed'}
 Lua "assert(loadfile('$($repo.Replace('\','/'))/tools/smoke/stream_probe.lua'))('info','$($prefix.Replace('\','/'))-info.json')"|Out-Null
 if(-not $ViewerOnly){
  Phase 'baseline_a' $false
  Phase 'bridge_a' $true
  Phase 'baseline_b' $false
  Phase 'bridge_b' $true
 }
 Write-Output $(if($ReaderOnly){'STARTING_READER'}else{'STARTING_GODOT'})
 Lua 'df.global.pause_state=true'|Out-Null
 $project="$repo/presentations/godot/project"
 if($ReaderOnly){
 $g=Start-ContainedProcess -Exe "$repo/build/tools/stream_reader_probe.exe" -Arguments "`"$prefix`"" -WorkingDir $repo
 }else{
 $g=Start-ContainedProcess -Exe $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' }) -Arguments "--path `"$project`" --script res://tests/stream_benchmark_live.gd --log-file `"$prefix-godot.log`"" -WorkingDir $project
 }
 $handle=$g.Handle
 $deadline=(Get-Date).AddSeconds(300)
 while(-not(Test-Path "$prefix-ready.json") -and (Get-Date)-lt $deadline){if($g.HasExited){throw 'Godot exited during startup'};Start-Sleep -Milliseconds 500}
 if(-not(Test-Path "$prefix-ready.json")){throw 'Godot readiness timeout'}
 if($ReaderOnly){Phase 'reader_only' $true $true}else{
 Phase 'viewer_static' $true $true
 Phase 'viewer_orbit' $true $true
 }
 Control 'quit'
 if(-not $g.WaitForExit(15000)){throw 'Godot exit timeout'}
 if(-not $ViewerOnly){Phase 'baseline_c' $false}
 Write-Output 'STREAM_BENCHMARK_PASS'
}finally{
 Exit-Df3dLane
 foreach($key in $old.Keys){[Environment]::SetEnvironmentVariable($key,$old[$key],'Process')}
}
