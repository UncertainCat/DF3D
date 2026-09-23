# Current bridge recordings and actual save/unload/reload, on a protected clone.
param(
    [string]$DfPath = $(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { 'C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress' }),
    [string]$SourceSave = $(if ($env:DF3D_SOURCE_SAVE) { $env:DF3D_SOURCE_SAVE } else { 'region5' }),
    [string]$ReuseTestSave = '',
    [string]$ReuseBackupManifest = ''
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Df3dLane.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SaveIsolation.psm1') -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$project = Join-Path $repo 'presentations/godot/project'
$appSave = Join-Path $env:APPDATA 'Bay 12 Games/Dwarf Fortress/save'
$steamSave = Join-Path $DfPath 'save'
$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
$out = Join-Path $repo "build/recorded-session-$suffix"
$cloneName = "df3d-gameplay-test-$suffix"
$backup = $null
$initialDirectories = @()
if ($SourceSave -notmatch '^[A-Za-z0-9_-]+$') { throw 'Expected one source save directory name' }
if ($ReuseTestSave) {
    if ($ReuseTestSave -notmatch '^df3d-gameplay-test-[a-f0-9]{12}$' -or -not (Test-Path -LiteralPath (Join-Path $appSave $ReuseTestSave))) { throw 'Expected existing disposable clone' }
    $cloneName = $ReuseTestSave
}
$clone = Join-Path $appSave $cloneName
New-Item -ItemType Directory -Path $out | Out-Null
$lua = (Join-Path $PSScriptRoot 'recorded-session-fixture.lua').Replace('\', '/')
$outLua = $out.Replace('\', '/')
$captureBinaries = [ordered]@{
    bridge = Join-Path $DfPath 'hack/plugins/df3d.plug.dll'
    godot_extension = Join-Path $project 'bin/df3d_godot.dll'
    native_game = Join-Path $DfPath 'Dwarf Fortress.exe'
    replay_validator = Join-Path $repo 'build/tools/fixture_evidence.exe'
    godot = $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' })
}
$binaryHashes = [ordered]@{}
foreach ($name in $captureBinaries.Keys) { $binaryHashes[$name] = (Get-FileHash -LiteralPath $captureBinaries[$name] -Algorithm SHA256).Hash }
@{ source_save_requested=$SourceSave; reused_clone=[bool]$ReuseTestSave; clone=$clone; binary_sha256=$binaryHashes; started_utc=[DateTime]::UtcNow.ToString('o') } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "$out/capture-start.json" -Encoding UTF8
function Native([string]$Code, [string]$Stage) {
    $receipt = "$outLua/receipt-$Stage"
    if ($Code.Contains(']]') -and $outLua.Contains(']]')) { throw 'Unsupported path' }
    $result = Invoke-DfhackRaw -CommandArgs @('lua', "$Code; local f=assert(io.open([[$receipt]],'w')); f:write([[$suffix]]); f:close()")
    $result.Output | Add-Content -LiteralPath "$out/native.log"
    if (-not (Test-Path -LiteralPath $receipt) -or (Get-Content -LiteralPath $receipt -Raw) -ne $suffix) { throw "Native stage failed: $Stage" }
}
try {
    Enter-Df3dLane -DfPath $DfPath -Port 5010
    $initialDirectories = @(Get-ChildItem -LiteralPath $appSave -Directory | ForEach-Object Name)
    if ($ReuseBackupManifest) {
        if (-not $ReuseTestSave) { throw 'Backup reuse requires an existing disposable clone' }
        $backup = Get-Content -LiteralPath $ReuseBackupManifest -Raw | ConvertFrom-Json
        $roots = @($steamSave, $appSave) | ForEach-Object { (Resolve-Path -LiteralPath $_).Path.TrimEnd('\', '/') }
        if ($backup.Roots.Count -ne 2 -or $backup.Roots[0] -ne $roots[0] -or $backup.Roots[1] -ne $roots[1] -or $cloneName -notin $backup.AllowedDirectories) { throw 'Backup does not cover this clone' }
        Assert-DfSaveBackupUnchanged -Manifest $backup
    } else {
        $backup = New-DfSaveBackup -SaveRoots @($steamSave, $appSave) -BackupRoot "$out-backup" -AllowedDirectories @('current', $cloneName)
    }
    if (-not $ReuseTestSave) { Copy-Item -LiteralPath (Join-Path $steamSave $SourceSave) -Destination $clone -Recurse }
    $env:DF3D_AUDIO_SILENT = '1'
    $env:DF3D_FIXTURE = ''
    $env:DF3D_SCREENSHOT = ''
    $env:DF3D_RECORDED_SESSION = $out
    Set-DfPrefs
    Install-DfMenuStartup -DfPath $DfPath
    $df = Start-Df3d -DfPath $DfPath
    $load = Start-ContainedProcess -Exe (Join-Path $repo 'build/tools/session_client.exe') -WorkingDir $repo -Arguments "load `"$($clone.Replace('\','/'))`""
    if (-not $load.WaitForExit(330000)) { throw 'Clone load timed out' }
    $state = & (Join-Path $repo 'build/tools/session_client.exe') status
    if ($LASTEXITCODE -ne 0 -or -not ($state -match 'SESSION phase=3 ') -or -not ($state -match [regex]::Escape("id=$($clone.Replace('\','/')) message="))) { throw 'Wrong fortress identity' }
    Native "assert(loadfile([[$lua]]))([[$outLua]], 'prepare')" 'prepare'
    $godot = Start-ContainedProcess -Exe $(if ($env:DF3D_GODOT) { $env:DF3D_GODOT } else { 'C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe' }) -WorkingDir $project -Arguments "--headless --path `"$project`" --script res://tests/recorded_session_live.gd --log-file `"$out/godot.log`""
    $handled = @{}
    $deadline = (Get-Date).AddSeconds(660)
    while (-not $godot.HasExited -and (Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath "$out/request.json") {
            try { $request = Get-Content -LiteralPath "$out/request.json" -Raw | ConvertFrom-Json } catch { $request = $null }
            $stage = [string]$request.stage
            if ($stage -and -not $handled.ContainsKey($stage)) {
                switch ($stage) {
                    'start-before' { Native "assert(dfhack.run_command('df3d','record','start',[[$outLua/before.df3dfix]])==0)" $stage }
                    'stop-before' { Native "assert(loadfile([[$lua]]))([[$outLua]], 'verify', '2'); assert(dfhack.run_command('df3d','record','stop')==0)" $stage }
                    'start-after' { Native "assert(loadfile([[$lua]]))([[$outLua]], 'verify', '2'); assert(dfhack.run_command('df3d','record','start',[[$outLua/after.df3dfix]])==0)" $stage }
                    'stop-after' { Native "assert(loadfile([[$lua]]))([[$outLua]], 'verify', '3'); assert(dfhack.run_command('df3d','record','stop')==0)" $stage }
                    default { throw "Unexpected fixture stage: $stage" }
                }
                $handled[$stage] = $true
                Set-Content -LiteralPath "$out/ack-$stage" -Value 'ok'
            }
        }
        Start-Sleep -Milliseconds 50
        $godot.Refresh()
    }
    if (-not $godot.HasExited) { throw 'Recorded session test timed out' }
    if (-not (Select-String -LiteralPath "$out/godot.log" -SimpleMatch 'RECORDED_SESSION_LIVE_PASS') -or (Select-String -LiteralPath "$out/godot.log" -Pattern 'SCRIPT ERROR|^ERROR:')) { throw "Recorded session integration failed; see $out/godot.log" }
    $target = Get-Content -LiteralPath "$out/target.json" -Raw | ConvertFrom-Json
    $env:PATH = "$(if ($env:DF3D_MINGW_BIN) { $env:DF3D_MINGW_BIN } else { 'C:\msys64\mingw64\bin' });$env:PATH"
    & (Join-Path $repo 'build/tools/fixture_evidence.exe') "$out/before.df3dfix" "$out/after.df3dfix" $target.tile.x $target.tile.y $target.tile.z $target.unit_id | Tee-Object -FilePath "$out/replay.log"
    if ($LASTEXITCODE -ne 0) { throw 'Recorded replay semantics failed' }
    Write-Output "RECORDED_SESSION_CAPTURE_PASS $out"
} finally {
    Exit-Df3dLane
    if ($backup) {
        if (Test-Path -LiteralPath "$out/lifecycle.json") {
            $lifecycle = Get-Content -LiteralPath "$out/lifecycle.json" -Raw | ConvertFrom-Json
            $savedPath = [IO.Path]::GetFullPath([string]$lifecycle.return_save)
            $savedName = [IO.Path]::GetFileName($savedPath)
            $sameClone = $savedPath -eq [IO.Path]::GetFullPath($clone)
            $newRegion = [IO.Path]::GetDirectoryName($savedPath) -eq [IO.Path]::GetFullPath($appSave) -and $savedName -match '^region[0-9]+$' -and $savedName -notin $initialDirectories
            if (-not $sameClone -and -not $newRegion) { throw 'Save-return did not name the owned clone or a new test-owned save' }
            if ($newRegion) { $backup.AllowedDirectories += $savedName }
            # Persist the allowance for this verified generated test save.
            $backup | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup.Backup 'manifest.json') -Encoding UTF8
        }
        Assert-DfSaveBackupUnchanged -Manifest $backup
        Set-Content -LiteralPath "$out/saves-unchanged.ok" -Value 'Non-test save hashes unchanged'
    }
    foreach ($name in $captureBinaries.Keys) {
        if ((Get-FileHash -LiteralPath $captureBinaries[$name] -Algorithm SHA256).Hash -ne $binaryHashes[$name]) { throw "Capture binary changed during run: $name" }
    }
    Set-Content -LiteralPath "$out/binaries-unchanged.ok" -Value 'Capture-start binary hashes verified at lane exit'
    Write-Output "Capture evidence retained: $out"
}
