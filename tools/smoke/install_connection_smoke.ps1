# Read-only title-screen connection check. Does not load or save a fortress.
param([string]$DfPath, [string]$GodotExe)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'tools\SteamPaths.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Df3dLane.psm1') -Force
$DfPath = Resolve-Df3dDfPath $DfPath
$GodotExe = Resolve-Df3dGodotExe $GodotExe
$project = Join-Path $repo 'presentations\godot\project'
$out = Join-Path $repo ('build\install-connection-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $out | Out-Null
$savedEnv = @{}
Get-ChildItem Env:DF3D_* | ForEach-Object { $savedEnv[$_.Name] = $_.Value }
$savedPath = $env:PATH
$viewer = $null
$entered = $false
try {
    Enter-Df3dLane -DfPath $DfPath
    $entered = $true
    Get-ChildItem Env:DF3D_* | Remove-Item
    $env:DF3D_DF_PATH = $DfPath
    $env:DF3D_CACHE_DIR = Join-Path $out 'asset-cache'
    # Exercise runtime loading without the developer's compiler DLLs on PATH.
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    $hashes = [ordered]@{}
    foreach ($file in @((Join-Path $DfPath 'Dwarf Fortress.exe'), (Join-Path $DfPath 'hack\plugins\df3d.plug.dll'), $GodotExe, (Join-Path $project 'bin\df3d_godot.dll'))) {
        $hashes[$file] = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    }
    $hashes | ConvertTo-Json | Set-Content -LiteralPath "$out\binaries.json"
    Set-DfPrefs
    Install-DfMenuStartup -DfPath $DfPath
    $df = Start-Df3d -DfPath $DfPath
    $deadline = (Get-Date).AddSeconds(90)
    $ready = $false
    while ((Get-Date) -lt $deadline) {
        $df.Refresh()
        if ($df.HasExited) { throw 'DF exited before bridge startup' }
        $status = Invoke-DfhackRaw @('df3d', 'status') -TimeoutSec 5
        $message = $status.Output -join "`n"
        if ($status.ExitCode -eq 0 -and $message -match 'mirroring enabled:\s+yes') { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'DF bridge did not become ready within 90 seconds' }
    $message | Set-Content -LiteralPath "$out\bridge.log"
    if ($message -notmatch 'map loaded:\s+no') { throw 'Expected title screen without a loaded fortress' }
    $viewer = Start-ContainedProcess -Exe $GodotExe -WorkingDir $project -Arguments "--headless --render-thread safe --path `"$project`" --quit-after 120 --log-file `"$out\viewer.log`""
    $deadline = (Get-Date).AddSeconds(90)
    while (-not $viewer.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 250; $viewer.Refresh() }
    if (-not $viewer.HasExited) { throw 'Viewer startup timed out' }
    $log = Get-Content -LiteralPath "$out\viewer.log" -Raw
    if ($log -notmatch 'df3d assets: DF 53\.16 build 24557528[^\r\n]+index rebuilt' -or $log -match '(?m)^(SCRIPT ERROR|ERROR):') {
        throw "Viewer did not cleanly load the pinned installation. See $out\viewer.log"
    }
    Write-Host "INSTALL_CONNECTION_PASS: discovered installation, live title-screen bridge, headless viewer with fresh asset cache, system-only PATH. Evidence: $out"
} finally {
    if ($viewer -and -not $viewer.HasExited) { Stop-Process -Id $viewer.Id -Force -ErrorAction SilentlyContinue }
    try { if ($entered) { Exit-Df3dLane } }
    finally {
        $env:PATH = $savedPath
        Get-ChildItem Env:DF3D_* | Remove-Item
        foreach ($name in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnv[$name]) }
    }
}
