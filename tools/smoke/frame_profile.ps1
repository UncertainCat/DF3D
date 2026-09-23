# Offline, uncapped full-scene frame profile. Run without another viewer/test.
param([string]$OutputName = 'perf-current', [Alias('Profile')][ValidateSet('off','basic','deep')][string]$Profiling='basic')
$ErrorActionPreference = 'Stop'
if ($OutputName -notmatch '^[A-Za-z0-9_-]+$') { throw 'OutputName must be a simple filename' }
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$profileEnv = @{
 DF3D_FIXTURE = "$repo/fixtures/recorded/mature_fort_pause_53.16.df3dfix"
 DF3D_FIXTURE_TICK = '1000'; DF3D_TOP_Z = '127'; DF3D_WINDOW = '24'
 DF3D_CAM_FOCUS = '96,94,127'; DF3D_CAM_DIST = '60'; DF3D_AUDIO_SILENT = '1'
 DF3D_PERF_OUT = "$repo/build/$OutputName"
 DF3D_PROFILE = $Profiling; DF3D_PROFILE_OUT = "$repo/build/$OutputName"
 DF3D_PERF_NO_RENDER_READBACK = '1'
}
$savedEnv = @{}
try {
 foreach ($key in $profileEnv.Keys) {
  $savedEnv[$key] = [Environment]::GetEnvironmentVariable($key,'Process')
  [Environment]::SetEnvironmentVariable($key,$profileEnv[$key],'Process')
 }
 $log = "$repo/build/$OutputName.log"
 & $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' }) --path "$repo/presentations/godot/project" --script res://tests/frame_profile.gd --log-file $log 2>&1 | Out-Null
 if ($LASTEXITCODE -ne 0 -or -not (Select-String -LiteralPath $log -SimpleMatch 'FRAME_PROFILE_PASS') -or (Select-String -LiteralPath $log -Pattern 'SCRIPT ERROR|^ERROR:')) { throw "Frame profile failed: $log" }
 Get-Content -LiteralPath "$repo/build/$OutputName.json"
} finally {
 foreach ($key in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($key,$savedEnv[$key],'Process') }
}
