# Offline GPU lifecycle regression; no DF process or save access.
param([ValidateSet('safe','separate')][string]$RenderThread='separate')
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$view = (Get-Content "$repo/fixtures/recorded/mature_fort_pause_53.16.manifest.json" -Raw | ConvertFrom-Json).view
$cfg=Join-Path $env:APPDATA 'Godot/app_userdata/DF3D/presentation.cfg'
$prior=if(Test-Path -LiteralPath $cfg){[IO.File]::ReadAllBytes($cfg)}else{$null}
$vars=@{
 DF3D_FIXTURE="$repo/fixtures/recorded/mature_fort_pause_53.16.df3dfix"
 DF3D_FIXTURE_TICK=[string]$view.tick; DF3D_TOP_Z=[string]$view.top_z; DF3D_WINDOW='24'; DF3D_AUDIO_SILENT='1'
 DF3D_CAM_FOCUS="$($view.x),$($view.y),$($view.top_z)"; DF3D_CAM_DIST=[string]$view.distance
 DF3D_THREAD_TEST_OUT="$repo/build/render-thread-$RenderThread"
}
$previous=@{}
$g=$null
try {
 foreach($key in $vars.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$vars[$key],'Process')}
 $log="$repo/build/render-thread-$RenderThread.log"
 $g=Start-Process -FilePath $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { 'C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe' }) -ArgumentList @('--render-thread',$RenderThread,'--path',"`"$repo/presentations/godot/project`"",'--script','res://tests/render_thread_fixture_test.gd','--log-file',"`"$log`"") -WindowStyle Hidden -PassThru
 $heldHandle=$g.Handle
 if(-not $g.WaitForExit(300000)){throw 'Render fixture timeout'}
 $text=Get-Content -LiteralPath $log -Raw
 if($g.ExitCode -ne 0 -or $text -notmatch 'RENDER_THREAD_FIXTURE_PASS' -or $text -match '(?m)SCRIPT ERROR|^ERROR:'){throw "Render fixture failed: $log"}
 Write-Output "Render fixture PASS: $RenderThread"
} finally {
 if($null -ne $g -and -not $g.HasExited){Stop-Process -Id $g.Id}
 foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
 if($null -ne $prior){[IO.File]::WriteAllBytes($cfg,$prior)}elseif(Test-Path -LiteralPath $cfg){Remove-Item -LiteralPath $cfg}
}
