param([switch]$Test)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'tools\SteamPaths.psm1') -Force
$godot = Resolve-Df3dGodotExe
$env:DF3D_MOCK_GODOT_ICON = Join-Path (Split-Path $godot -Parent) 'icon.png'
# Actual installation is an artwork source only. Mock target paths are independent.
$env:DF3D_DF_PATH = Resolve-Df3dDfPath
$scratch = Join-Path $repo 'build\setup-mock'
New-Item -ItemType Directory -Force $scratch | Out-Null
$env:DF3D_CACHE_DIR = Join-Path $scratch 'assets'
$env:DF3D_MOCK_CAPTURE = Join-Path $scratch 'acknowledgment.png'
$env:PATH = "C:\msys64\mingw64\bin;$env:PATH"
$arguments = @('--path', ('"' + (Join-Path $repo 'presentations\godot\project') + '"'), '--script', 'res://tests/setup_mock.gd', '--log-file', ('"' + (Join-Path $scratch 'mock.log') + '"'))
if ($Test) { $arguments += @('--', '--self-test') }
# The user requested an interactive harness; this window is intentionally visible.
$process = Start-Process -FilePath $godot -ArgumentList $arguments -PassThru
if ($Test) {
    if (-not $process.WaitForExit(60000)) { $process.Kill(); throw 'Setup mock timed out' }
    Get-Content (Join-Path $scratch 'mock.log')
    if ($process.ExitCode -ne 0 -or -not (Select-String -Path (Join-Path $scratch 'mock.log') -Pattern '^SETUP_MOCK_PASS$' -Quiet)) { throw 'Setup mock failed' }
}
