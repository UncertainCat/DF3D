# Exercise an exact shipped artifact from relocated paths, never install into the user's game.
param(
    [Parameter(Mandatory=$true)][string]$Artifact,
    [string]$DfPath,
    [string]$SourceSave
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'tools\SteamPaths.psm1') -Force
Import-Module (Join-Path $repo 'tools\smoke\Df3dLane.psm1') -Force
$DfPath = Resolve-Df3dDfPath $DfPath
$Artifact = (Resolve-Path -LiteralPath $Artifact).Path
if (@(Get-Process 'Dwarf Fortress' -ErrorAction SilentlyContinue).Count) { throw 'Close DF before the package smoke check' }
$out = Join-Path $repo ('build\package smoke ' + [guid]::NewGuid().ToString('N'))
$game = Join-Path $out 'Steam library\steamapps\common\Dwarf Fortress'
$extracted = Join-Path $out 'Extracted package'
New-Item -ItemType Directory -Path $game | Out-Null
Write-Host "[package] Evidence and isolated game: $out"
$moved = Join-Path $out 'DF3D.exe'
Copy-Item -LiteralPath $Artifact -Destination $moved
# Only the test directory receives game files. They never enter release staging.
foreach ($folder in @('data', 'prefs', 'licenses', 'mods')) {
    if (Test-Path -LiteralPath (Join-Path $DfPath $folder)) { Copy-Item -LiteralPath (Join-Path $DfPath $folder) -Destination (Join-Path $game $folder) -Recurse }
}
foreach ($file in Get-ChildItem -LiteralPath $DfPath -File) {
    if ($file.Name -eq 'Dwarf Fortress.exe' -or ($file.Extension -eq '.dll' -and $file.Name -notmatch '^dfhack|^dfhooks')) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $game $file.Name)
    }
}
$save = $null
if ($SourceSave) {
    $source = (Resolve-Path -LiteralPath $SourceSave).Path
    $save = Join-Path $game 'save\df3d-package-test'
    New-Item -ItemType Directory -Path (Split-Path $save) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $save -Recurse
}
$saved = @{}
foreach ($name in @('PATH','APPDATA','LOCALAPPDATA')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
Get-ChildItem Env:DF3D_* | ForEach-Object { $saved[$_.Name] = $_.Value }
$entered = $false
$journal = $null
try {
    Get-ChildItem Env:DF3D_* | Remove-Item
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    $env:APPDATA = Join-Path $out 'Profile\Roaming'
    $env:LOCALAPPDATA = Join-Path $out 'Profile\Local'
    New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
    $p = Start-Process -FilePath $moved -ArgumentList '--self-test' -WindowStyle Hidden -PassThru
    if (-not $p.WaitForExit(90000) -or $p.ExitCode -ne 0) { throw "Launcher self-test failed. See $env:LOCALAPPDATA\DF3D\launcher.log" }
    $p = Start-Process -FilePath $moved -ArgumentList ('--extract-only "' + $extracted + '"') -WindowStyle Hidden -PassThru
    if (-not $p.WaitForExit(90000) -or $p.ExitCode -ne 0) { throw 'Relocated extraction failed' }
    [Reflection.Assembly]::LoadFrom($moved) | Out-Null
    $manifest = [DF3D.Release.Package]::ReadManifest($extracted)
    $journal = [DF3D.Release.Package]::Install($extracted, $manifest, $game)
    $prefsHash = (Get-FileHash -LiteralPath (Join-Path $game 'prefs\init.txt')).Hash
    Enter-Df3dLane -DfPath $game -Port 5010
    $entered = $true
    $env:DF3D_DF_PATH = $game
    $env:DF3D_CACHE_DIR = Join-Path $out 'Fresh assets'
    $env:DF3D_RELEASE = '1'
    $env:DF3D_AUDIO_SILENT = '1'
    $env:DF3D_PROFILE = 'off'
    Set-DfPrefs
    Install-DfMenuStartup -DfPath $game
    $df = Start-Df3d -DfPath $game
    $deadline = (Get-Date).AddSeconds(120)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        $df.Refresh(); if ($df.HasExited) { throw 'Packaged bridge host exited during startup' }
        $status = Invoke-DfhackRaw @('df3d','status') -TimeoutSec 5
        if ($status.ExitCode -eq 0 -and ($status.Output -join "`n") -match 'mirroring enabled:\s+yes') { $ready = $true; break }
        Start-Sleep -Milliseconds 250
    }
    if (-not $ready) { throw 'Packaged bridge startup timed out' }
    $status.Output | Set-Content -LiteralPath "$out\bridge.log"
    $viewerExe = Join-Path $extracted 'viewer\DF3D.exe'
    $viewer = Start-ContainedProcess -Exe $viewerExe -WorkingDir (Split-Path $viewerExe) -Arguments "--headless --render-thread safe --quit-after 120 --log-file `"$out\headless.log`""
    $null = $viewer.Handle
    if (-not $viewer.WaitForExit(90000) -or $viewer.ExitCode -ne 0) { throw 'Exported headless startup failed' }
    $log = Get-Content -LiteralPath "$out\headless.log" -Raw
    if ($log -notmatch 'index rebuilt' -or $log -match '(?m)^(SCRIPT ERROR|ERROR):') { throw 'Exported fresh asset startup failed' }
    if ($save) {
        $client = Start-ContainedProcess -Exe (Join-Path $repo 'build\tools\session_client.exe') -WorkingDir $repo -Arguments "load `"$($save.Replace('\','/'))`""
        $null = $client.Handle
        if (-not $client.WaitForExit(330000) -or $client.ExitCode -ne 0) { throw 'Disposable fortress load failed' }
        $env:DF3D_SCREENSHOT = Join-Path $out 'fortress.png'
        $viewer = Start-ContainedProcess -Exe $viewerExe -WorkingDir (Split-Path $viewerExe) -Arguments "--log-file `"$out\gpu.log`""
        $null = $viewer.Handle
        if (-not $viewer.WaitForExit(180000) -or $viewer.ExitCode -ne 0) { throw 'Exported GPU viewer failed' }
        $frame = Get-Content -LiteralPath "$out\fortress.png.txt" -Raw
        if ($frame -notmatch 'source=live mirror' -or $frame -notmatch 'terrain_loaded=true' -or $frame -notmatch 'assets_ok=true') { throw 'GPU capture did not load live terrain/assets' }
        $gpuLog = Get-Content -LiteralPath "$out\gpu.log" -Raw
        if ($gpuLog -match '(?m)^\s*(SCRIPT ERROR|ERROR):') { throw 'GPU capture emitted errors; inspect gpu.log before accepting the artifact' }
    }
    $df.Refresh()
    if ($df.HasExited) { throw 'Viewer exit unexpectedly terminated Dwarf Fortress' }
    Exit-Df3dLane
    $entered = $false
    if ((Get-FileHash -LiteralPath (Join-Path $game 'prefs\init.txt')).Hash -ne $prefsHash) { throw 'Session did not restore preferences' }
    [DF3D.Release.Package]::Restore($journal)
    $journal = $null
    if (Test-Path -LiteralPath (Join-Path $game 'hack\plugins\df3d.plug.dll')) { throw 'Bridge uninstall left plugin behind' }
    @{artifact=$Artifact;sha256=(Get-FileHash -LiteralPath $Artifact).Hash;version=$manifest.version;extraction='pass';install_restore='pass';headless='pass';gpu_capture=[bool]$save;system_only_path=$true;separate_machine=$false} | ConvertTo-Json | Set-Content -LiteralPath "$out\result.json"
    Write-Host "PACKAGE_SMOKE_PASS: $out"
} finally {
    try { if ($entered) { Exit-Df3dLane } }
    finally {
        Get-ChildItem Env:DF3D_* | Remove-Item
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}
