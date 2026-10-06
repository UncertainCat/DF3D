# Protected owned acceptance: two restarts of one disposable, never-saved clone.
param([string]$DfPath=$(if($env:DF3D_DF_PATH){$env:DF3D_DF_PATH}else{'C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'}),
    [ValidateSet('restart','inprocess')][string]$Route='restart',
    [string]$OwnedSave='', [string]$OwnedSaveManifest='')
$ErrorActionPreference='Stop'
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
Import-Module "$PSScriptRoot/SaveIsolation.psm1" -Force
$out="$repo/build/reload-lane-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
$entered=$false;$prepared=$false;$g=$null;$summary='failed startup';$manifest=$null
$oldInput=$env:DF3D_RELOAD_LANE
function Write-Atomic([string]$Path,$Value) {
    [IO.File]::WriteAllText("$Path.tmp",($Value | ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath "$Path.tmp" -Destination $Path
}
function Fixture([string]$Mode,[int]$UnitId=-1) {
    $arg=if($UnitId -ge 0){",$UnitId"}else{''}
    $reply=Invoke-DfhackRaw -CommandArgs @('lua',"assert(loadfile([==[$repo/tools/smoke/reload-lane-fixture.lua]==]))([==[$out]==],'$Mode'$arg)")
    $reply.Output | Add-Content "$out/native.log"
    $marker=if($Mode -eq 'restore'){'RELOAD_FIXTURE_RESTORED'}else{'FIXTURE_READY'}
    if(($reply.Output -join "`n") -notmatch $marker){throw "Reload fixture $Mode failed (exit $($reply.ExitCode))"}
}
try {
    Enter-Df3dLane -DfPath $DfPath;$entered=$true
    Get-FileHash -Algorithm SHA256 "$DfPath/hack/plugins/df3d.plug.dll","$repo/presentations/godot/project/bin/df3d_godot.dll","$repo/build/tools/session_client.exe" | Format-List | Out-File "$out/binaries.log"
    $roots=@((Join-Path $DfPath 'save'),(Join-Path $env:APPDATA 'Bay 12 Games/Dwarf Fortress/save'))
    if ($OwnedSave) {
        if (-not $OwnedSaveManifest) { throw 'Reused owned save requires its verified SHA256 manifest' }
        $clone=[IO.Path]::GetFullPath($OwnedSave).Replace('\','/').TrimEnd('/')
        $parent=[IO.Path]::GetDirectoryName($clone).Replace('\','/')
        if ($parent -notin @($roots | ForEach-Object {[IO.Path]::GetFullPath($_).Replace('\','/')})) { throw 'Owned save must be a direct child of a native save root' }
        $actual=(@(Get-ChildItem -LiteralPath $clone -File -Recurse | ForEach-Object {
            $_.FullName.Substring($clone.Length).TrimStart('\','/')+' '+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        } | Sort-Object) -join "`n")
        if ($actual -cne (Get-Content -LiteralPath $OwnedSaveManifest -Raw).TrimEnd("`r","`n")) { throw 'Reused owned save differs from its verified manifest' }
        # No writer is selected. Scope hashing to this already-owned source;
        # write-capable acceptance continues to protect both complete save roots.
        $roots=@($clone)
    } else {
    if ($OwnedSaveManifest) { throw 'OwnedSaveManifest requires OwnedSave' }
    $source=Join-Path $roots[0] 'region5'
    if(-not(Test-Path -LiteralPath $source)){throw 'INCOMPLETE source region5 absent'}
    $clone=(Join-Path $roots[1] ('df3d-reload-'+[guid]::NewGuid().ToString('N'))).Replace('\','/')
    if(Test-Path -LiteralPath $clone){throw 'Disposable clone already exists'}
    New-Item -ItemType Directory -Force -Path $roots[1] | Out-Null
    Copy-Item -LiteralPath $source -Destination $clone -Recurse
    foreach($file in Get-ChildItem -LiteralPath $source -Recurse -File){
        $rel=$file.FullName.Substring($source.Length).TrimStart('\','/')
        if((Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath (Join-Path $clone $rel)).Hash){throw 'Clone hash mismatch'}
    }
    }
    Write-Host '[lane] hashing initial save roots'
    $records=[System.Collections.Generic.List[object]]::new()
    for($i=0;$i -lt $roots.Count;$i++){
        foreach($file in Get-ChildItem -LiteralPath $roots[$i] -Recurse -File){
            $records.Add([pscustomobject]@{Root=$i;Path=$file.FullName.Substring($roots[$i].Length).TrimStart('\','/');Hash=(Get-FileHash -LiteralPath $file.FullName).Hash})
        }
    }
    $manifest=[pscustomobject]@{Roots=$roots;Backup=$out;AllowedDirectories=@('current');Files=$records.ToArray()}
    Write-Host "[lane] recorded $($records.Count) initial save-file hashes"
    $manifest | ConvertTo-Json -Depth 5 | Set-Content "$out/manifest.json"
    Set-DfPrefs;Install-DfMenuStartup -DfPath $DfPath
    Start-Df3d -DfPath $DfPath | Out-Null
    & "$repo/build/tools/session_client.exe" load $clone *> "$out/initial-load.log"
    if($LASTEXITCODE -ne 0){throw 'INCOMPLETE initial load failed'}
    Fixture 'mark';$prepared=$true
    $markerId=[int](Get-Content "$out/marker.json" -Raw | ConvertFrom-Json).id
    $env:DF3D_RELOAD_LANE=$out
    $godot=if($env:DF3D_GODOT){$env:DF3D_GODOT}else{'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'}
    $g=Start-ContainedProcess -Exe $godot -Arguments "--headless --path `"$repo/presentations/godot/project`" --script res://tests/reload_lane_live.gd --log-file `"$out/godot.log`"" -WorkingDir "$repo/presentations/godot/project"
    $deadline=(Get-Date).AddSeconds(2000)
    while(-not $g.HasExited -and (Get-Date) -lt $deadline){
        if(Test-Path "$out/verify.txt"){
            $index=[int](Get-Content "$out/verify.txt" -Raw);Remove-Item -LiteralPath "$out/verify.txt"
            $prepared=$false
            try {
                $restart=Restart-Df3dFortress -Route $Route -SaveId $clone -SaveRoots $roots -EvidenceDir "$out/restart-$index"
                if($restart.Status -eq 'ready'){
                    Fixture 'verify' $markerId;$prepared=$true
                    if($index -lt 2){Fixture 'mark' $markerId}
                    Write-Atomic "$out/ack-$index" @{pid=$restart.Pid;epoch=[string]$restart.Epoch;route=$restart.Route}
                }else{Write-Atomic "$out/$($restart.Status)-$index" @{reason=$restart.Reason}}
            }catch{Write-Atomic "$out/failed-$index" @{reason=$_.Exception.Message}}
        }
        Start-Sleep -Milliseconds 100;$g.Refresh()
    }
    if(-not $g.HasExited){throw 'INCOMPLETE reload lane deadline hit'}
    if(-not(Test-Path "$out/result.json")){throw 'Godot exited without reload result'}
    $result=Get-Content "$out/result.json" -Raw | ConvertFrom-Json
    $summary="$($result.status) $($result.reason)"
    if($result.status -eq 'passed' -and $g.ExitCode -ne 0){throw "Godot exit [$($g.ExitCode)] disagrees with result"}
}catch{$summary=if($_.Exception.Message.StartsWith('INCOMPLETE ')){'incomplete '+$_.Exception.Message.Substring(11)}else{'failed '+$_.Exception.Message}}
finally{
    try{
        if($g -and -not $g.HasExited){$g.Kill();$g.WaitForExit()}
        if($prepared){Fixture 'restore'}
    }catch{$summary='failed teardown: '+$_.Exception.Message}
    finally{
        try{if($entered){Exit-Df3dLane}}catch{$summary='failed teardown: '+$_.Exception.Message}
        try{if($manifest){Write-Host '[lane] verifying final save roots';Assert-DfSaveBackupUnchanged $manifest | Out-Null}}catch{$summary='failed save integrity: '+$_.Exception.Message}
        $env:DF3D_RELOAD_LANE=$oldInput
        $summary | Set-Content "$out/summary.txt"
        # Let the gate classify engine diagnostics as well as our result marker.
        if(Test-Path "$out/godot.log"){Get-Content "$out/godot.log" | Write-Output}
        Write-Output "$summary -- $out"
    }
}
if($summary.StartsWith('passed')){Write-Output 'RELOAD_LANE_PASS';exit 0}
if($summary.StartsWith('incomplete')){Write-Output "QA_INCOMPLETE $summary";exit 77}
exit 1
