# Protected live lane: designation acceptance on a disposable clone save (see -GuardProbe).
param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$SaveId,[string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}),[switch]$GuardProbe)
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
$out="$repo/build/designation-acceptance-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
Get-FileHash -Algorithm SHA256 "$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll" | Format-List | Out-File "$out/binaries.log"
try {
 Enter-Df3dLane -DfPath $DfPath -Port 5010
 Set-DfPrefs
 Install-DfMenuStartup -DfPath $DfPath
 $d=Start-Df3d -DfPath $DfPath
 & "$repo/build/tools/session_client.exe" load $SaveId *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'Load failed'}
 $result=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile('$repo/tools/smoke/designation-acceptance-fixture.lua'))('$out')")
 $result.Output | Set-Content "$out/fixture.log"
 if(($result.Output -join "`n") -notmatch 'FIXTURE_READY'){throw 'Fixture failed'}
 if($GuardProbe){
  $before=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile('$repo/tools/smoke/command-guard-state.lua'))('before')")
  $before.Output | Set-Content "$out/guard-native.log"
  if(($before.Output -join "`n") -notmatch 'GUARD_BASELINE'){throw 'Guard baseline failed'}
  $cases=Get-Content -Raw "$out/cases.json" | ConvertFrom-Json;$tile=$cases[0].tile
  & "$repo/build/tools/command_guard_live.exe" $tile.x $tile.y $tile.z *> "$out/guard-client.log"
  if($LASTEXITCODE -ne 0){throw "Guard client failed: $out/guard-client.log"}
  $after=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile('$repo/tools/smoke/command-guard-state.lua'))('after')")
  $after.Output | Add-Content "$out/guard-native.log"
  if(($after.Output -join "`n") -notmatch 'GUARD_NATIVE_UNCHANGED'){throw 'Guard native state changed'}
 }
 $env:DF3D_DESIGNATION_ACCEPTANCE=$out
 $project="$repo/presentations/godot/project"
 $g=Start-ContainedProcess -Exe $(if($env:DF3D_GODOT){$env:DF3D_GODOT}else{'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'}) -Arguments "--headless --path `"$project`" --script res://tests/designation_acceptance_live.gd --log-file `"$out/godot.log`"" -WorkingDir $project
 $deadline=(Get-Date).AddSeconds(120)
 while(-not $g.HasExited -and (Get-Date) -lt $deadline) {
  if(Test-Path "$out/verify.txt") {
   $index=[int](Get-Content "$out/verify.txt")
   Remove-Item -LiteralPath "$out/verify.txt"
   $r=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile('$repo/tools/smoke/designation-acceptance-verify.lua'))($index)")
   $r.Output | Add-Content "$out/native.log"
   if(($r.Output -join "`n") -notmatch 'SEMANTIC_PASS'){throw "Native verification $index failed: $($r.Output)"}
   'ok' | Set-Content "$out/ack-$index"
  }
  Start-Sleep -Milliseconds 100
  $g.Refresh()
 }
 if(-not $g.HasExited){throw 'Godot timeout'}
 if(-not (Select-String -LiteralPath "$out/godot.log" -SimpleMatch 'DESIGNATION ACCEPTANCE PASS')){throw "Godot failed: $out/godot.log"}
 Write-Host "PASS $out"
} finally {Stop-Df3d;Exit-Df3dLane}
