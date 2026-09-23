# Offline fixed-tick camera movement regression; no DF process or save access.
param([ValidateSet('billboard','flat')][string]$Style='billboard',[ValidatePattern('^[A-Za-z0-9_-]+$')][string]$OutputName='billboard-camera-motion')
$RenderThread='safe'
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$cfg=Join-Path $env:APPDATA 'Godot/app_userdata/DF3D/presentation.cfg'
$prior=if(Test-Path -LiteralPath $cfg){[IO.File]::ReadAllBytes($cfg)}else{$null}
$vars=@{
 DF3D_FIXTURE="$repo/fixtures/recorded/mature_fort_pause_53.16.df3dfix"
 DF3D_FIXTURE_TICK='1000'; DF3D_TOP_Z='127'; DF3D_WINDOW='24'; DF3D_AUDIO_SILENT='1'
 DF3D_CAM_FOCUS='96,94,127'; DF3D_CAM_DIST='60'
 DF3D_BILLBOARD_OUT="$repo/build/$OutputName.json"; DF3D_MOTION_STYLE=$Style; DF3D_PROFILE='off'
}
$previous=@{}
$g=$null
try {
 foreach($key in $vars.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$vars[$key],'Process')}
 $log="$repo/build/$OutputName.log"
 $g=Start-Process -FilePath $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' }) -ArgumentList @('--render-thread',$RenderThread,'--path',"`"$repo/presentations/godot/project`"",'--script','res://tests/billboard_motion_test.gd','--log-file',"`"$log`"") -WindowStyle Hidden -PassThru
 $heldHandle=$g.Handle
 $deadline=(Get-Date).AddSeconds(300)
 while((Get-Date) -lt $deadline){if($g.WaitForExit(1000)){break}}
 if(-not $g.HasExited){throw 'Camera motion timeout'}
 $text=Get-Content -LiteralPath $log -Raw
 if($g.ExitCode -ne 0 -or $text -notmatch 'BILLBOARD_MOTION_TEST_PASS' -or $text -match '(?m)SCRIPT ERROR|^ERROR:'){throw "Camera motion failed: $log"}
 Write-Output "Camera motion PASS: $Style"
} finally {
 if($null -ne $g -and -not $g.HasExited){Stop-Process -Id $g.Id}
 foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
 if($null -ne $prior){[IO.File]::WriteAllBytes($cfg,$prior)}elseif(Test-Path -LiteralPath $cfg){Remove-Item -LiteralPath $cfg}
}
