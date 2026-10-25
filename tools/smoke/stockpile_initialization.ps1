# Reuse a previously verified disposable clone. No saves and no process restart.
param(
 [Parameter(Mandatory=$true)][string]$CloneEvidence,
 [string]$DfPath='C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'
)
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
$env:Path='C:/msys64/mingw64/bin;'+$env:Path
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
$clone=(Get-Content "$CloneEvidence/clone-path.txt" -Raw).Trim()
$expected=(Get-Content "$CloneEvidence/clone-manifest.txt" -Raw).TrimEnd("`r","`n")
function Manifest {
 return (@(Get-ChildItem -LiteralPath $clone -Recurse -File | ForEach-Object {
  $_.FullName.Substring($clone.Length).TrimStart('\','/')+' '+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
 } | Sort-Object) -join "`n")
}
if((Manifest) -cne $expected){throw 'Disposable clone differs from verified manifest'}
$out="$repo/build/stockpile-initialization-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
$entered=$false;$summary='failed';$g=$null
$oldInput=$env:DF3D_AREAS_ACCEPTANCE
function Invoke-Lua([string]$Script,[string]$Arguments) {
 $r=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile([==[$PSScriptRoot/$Script]==]))($Arguments)")
 $r.Output | Add-Content "$out/native.log"
 if($r.ExitCode -ne 0){throw "Native check failed: $Script"}
 return ($r.Output -join "`n")
}
try {
 Enter-Df3dLane -DfPath $DfPath -Port 5010;$entered=$true
 Get-FileHash "$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll",$PSCommandPath | ConvertTo-Json | Set-Content "$out/inputs.json"
 Set-DfPrefs;Install-DfMenuStartup -DfPath $DfPath
 Start-Df3d -DfPath $DfPath | Out-Null
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'Source load failed'}
 if((Invoke-Lua 'areas-acceptance-fixture.lua' "[==[$out]==]") -notmatch 'FIXTURE_READY'){throw 'Fixture failed'}
 $env:DF3D_AREAS_ACCEPTANCE=$out
 $project="$repo/presentations/godot/project"
 $godot=if($env:DF3D_GODOT){$env:DF3D_GODOT}else{'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'}
 $g=Start-ContainedProcess -Exe $godot -Arguments "--headless --render-thread safe --path `"$project`" --script res://tests/stockpile_initialization_live.gd --log-file `"$out/godot.log`"" -WorkingDir $project
 $deadline=(Get-Date).AddSeconds(600)
 while(-not $g.HasExited -and (Get-Date) -lt $deadline) {
  if(Test-Path "$out/verify.txt") {
   $index=[int](Get-Content "$out/verify.txt" -Raw)
   Remove-Item -LiteralPath "$out/verify.txt"
   if((Invoke-Lua 'stockpile-initialization-verify.lua' "[==[$out]==],$index") -notmatch 'SEMANTIC_PASS'){throw "Native verification $index failed"}
   [IO.File]::WriteAllText("$out/ack-$index.tmp",'ok')
   Move-Item -LiteralPath "$out/ack-$index.tmp" -Destination "$out/ack-$index"
  }
  Start-Sleep -Milliseconds 100;$g.Refresh()
 }
 if(-not $g.HasExited){throw 'Driver timed out; no command replay'}
 $result=Get-Content "$out/result.json" -Raw | ConvertFrom-Json
 if($result.status -ne 'passed' -or $g.ExitCode -ne 0){throw "Driver $($result.status): $($result.reasons -join '; ')"}
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
 if($LASTEXITCODE -ne 0){throw 'Diagnostic parser failed'}
 $diagnostics=Get-Content "$out/diagnostics.json" -Raw | ConvertFrom-Json
 if(@($diagnostics.unclassified).Count){throw 'Unclassified engine diagnostics'}
 if((Invoke-Lua 'areas-acceptance-verify.lua' "[==[$out]==],'final'") -notmatch 'SEMANTIC_PASS'){throw 'Final pause check failed'}
 $summary='passed'
 if(@($diagnostics.known_engine).Count){$summary='passed_with_known_issues'}
} catch {$summary='failed '+$_.Exception.Message}
finally {
 try {if($entered){Exit-Df3dLane}} catch {$summary='failed teardown '+$_.Exception.Message}
 try {if((Manifest) -cne $expected){throw 'Source changed'};'Owned source unchanged' | Set-Content "$out/save-preservation.txt"} catch {$summary='failed preservation '+$_.Exception.Message}
 $env:DF3D_AREAS_ACCEPTANCE=$oldInput
 $summary | Set-Content "$out/summary.txt";Write-Output "$summary -- $out"
}
if($summary -notin @('passed','passed_with_known_issues')){exit 1}
