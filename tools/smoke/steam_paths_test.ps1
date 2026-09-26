# Synthetic Steam layouts; no game, registry changes or installed assets needed.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\SteamPaths.psm1') -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$testRoot = Join-Path $repo ('build\steam paths ' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('DF3D_STEAM_ROOT', 'DF3D_DF_PATH', 'DF3D_GODOT')) {
    $saved[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $null)
}
function Assert-Equal($actual, $expected) {
    if ($actual -ne $expected) { throw "Expected '$expected', got '$actual'" }
}
function Assert-Fails([scriptblock]$action, [string]$message) {
    try { & $action } catch {
        if ($_.Exception.Message -notlike "*$message*") { throw }
        return
    }
    throw "Expected failure containing '$message'"
}
try {
    $steam = Join-Path $testRoot 'Steam root'
    $library = Join-Path $testRoot 'Secondary library [games]'
    $df = Join-Path $library 'steamapps\common\Custom DF folder'
    $godot = Join-Path $library 'steamapps\common\Custom Godot folder\godot.windows.opt.tools.64.exe'
    New-Item -ItemType Directory -Force (Join-Path $steam 'steamapps'), $df, (Split-Path $godot) | Out-Null
    [IO.File]::WriteAllText((Join-Path $df 'Dwarf Fortress.exe'), '')
    [IO.File]::WriteAllText($godot, '')
    $escaped = $library.Replace('\', '\\')
    $folders = Join-Path $steam 'steamapps\libraryfolders.vdf'
    [IO.File]::WriteAllText($folders, '"libraryfolders" { "1" { "path" "' + $escaped + '" "apps" {} } }')
    $dfManifest = Join-Path $library 'steamapps\appmanifest_975370.acf'
    [IO.File]::WriteAllText($dfManifest, '"AppState" { "appid" "975370" "installdir" "Custom DF folder" }')
    # A stale primary-library manifest must not hide a valid secondary install.
    [IO.File]::WriteAllText((Join-Path $steam 'steamapps\appmanifest_975370.acf'), '"AppState" { "appid" "975370" "installdir" "removed game" }')
    [IO.File]::WriteAllText((Join-Path $library 'steamapps\appmanifest_404790.acf'), '"AppState" { "appid" "404790" "installdir" "Custom Godot folder" }')
    $env:DF3D_STEAM_ROOT = $steam
    Assert-Equal (Resolve-Df3dDfPath) $df
    Assert-Equal (Resolve-Df3dGodotExe) $godot
    # Legacy library metadata is accepted too.
    [IO.File]::WriteAllText($folders, '"libraryfolders" { "1" "' + $escaped + '" }')
    Assert-Equal (Resolve-Df3dDfPath) $df
    $env:DF3D_DF_PATH = Join-Path $testRoot 'missing override'
    Assert-Fails { Resolve-Df3dDfPath } 'explicit override'
    Assert-Equal (Resolve-Df3dDfPath -DfPath $df) $df
    $env:DF3D_GODOT = Join-Path $testRoot 'missing godot.exe'
    Assert-Fails { Resolve-Df3dGodotExe } 'explicit override'
    Assert-Equal (Resolve-Df3dGodotExe -GodotExe $godot) $godot
    $env:DF3D_DF_PATH = $df
    $env:DF3D_GODOT = $godot
    $env:DF3D_STEAM_ROOT = Join-Path $testRoot 'no Steam'
    Assert-Equal (Resolve-Df3dDfPath) $df
    Assert-Equal (Resolve-Df3dGodotExe) $godot
    $env:DF3D_DF_PATH = $null
    $env:DF3D_GODOT = $null
    Assert-Fails { Resolve-Df3dDfPath } '975370'
    $env:DF3D_STEAM_ROOT = $steam
    [IO.File]::WriteAllText($dfManifest, '"AppState" { "appid" "wrong" "installdir" "Custom DF folder" }')
    Assert-Fails { Resolve-Df3dDfPath } '975370'
    [IO.File]::WriteAllText($dfManifest, '"AppState" { "appid" "975370" "installdir" "removed game" }')
    Assert-Fails { Resolve-Df3dDfPath } '975370'
    [IO.File]::WriteAllText($folders, '"libraryfolders" {')
    Assert-Fails { Resolve-Df3dDfPath } 'Invalid Steam metadata'
    Write-Host 'STEAM_PATHS_PASS: secondary/legacy libraries, spaces/brackets, overrides, missing installs and malformed metadata'
} finally {
    foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build')) + '\'
    if (-not $resolved.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
