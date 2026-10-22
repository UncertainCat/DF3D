# Real single-window handoff and teardown; only a disposable DF copy is writable.
param([Parameter(Mandatory=$true)][string]$Payload, [Parameter(Mandatory=$true)][string]$Game,
    [ValidateSet('startup-failure','close','app-crash','df-crash','controller-crash')][string[]]$Cases = @('startup-failure','close','app-crash','df-crash','controller-crash'))
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Import-Module (Join-Path $repo 'tools/smoke/Df3dLane.psm1') -Force
$Payload = (Resolve-Path -LiteralPath $Payload).Path
$Game = (Resolve-Path -LiteralPath $Game).Path
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build')) + '\'
if (-not $Game.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Use a disposable game copy under build.' }
$out = Join-Path $repo ('build/setup-session-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$exe = Join-Path $out 'controller-test.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /main:SetupUiTests "/out:$exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $PSScriptRoot 'Launcher.cs') (Join-Path $PSScriptRoot 'SetupUiTests.cs')
if ($LASTEXITCODE) { throw 'Controller compilation failed' }
$saved = @{}
foreach ($name in @('LOCALAPPDATA','APPDATA','PATH')) { $saved[$name] = [Environment]::GetEnvironmentVariable($name) }
Get-ChildItem Env:DF3D_* | ForEach-Object { $saved[$_.Name] = $_.Value }
$entered = $false
$journal = $null
$controller = $null
$client = Join-Path $Game 'hack/dfhack-run.exe'
$parkedClient = Join-Path $out 'dfhack-run.exe'
try {
    Enter-Df3dLane -DfPath $Game -Port 5000
    $entered = $true
    Get-ChildItem Env:DF3D_* | Remove-Item
    $env:LOCALAPPDATA = Join-Path $out 'Local'
    $env:APPDATA = Join-Path $out 'Roaming'
    $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
    $env:DF3D_CACHE_DIR = Join-Path $out 'assets'
    [Reflection.Assembly]::LoadFrom($exe) | Out-Null
    $manifest = [DF3D.Release.Package]::ReadManifest($Payload)
    $journal = [DF3D.Release.Package]::Install($Payload, $manifest, $Game)
    Set-DfPrefs
    New-Item -ItemType Directory -Force (Join-Path $env:LOCALAPPDATA 'DF3D') | Out-Null
    @{installation=$Game; acknowledgment='1'; journal=$journal} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $env:LOCALAPPDATA 'DF3D/launcher.json') -Encoding ascii
    $script = Join-Path $repo 'presentations/godot/project/tests/setup_session_test.gd'
    foreach ($case in $Cases) {
        Write-Host "[setup-session] $case"
        $env:DF3D_SETUP_CASE = $case
        $report = Join-Path $out ($case + '.json')
        $env:DF3D_SETUP_REPORT = $report
        if ($case -eq 'startup-failure') { Move-Item -LiteralPath $client -Destination $parkedClient }
        $children = @{}
        try {
            $controller = Start-Process -FilePath $exe -ArgumentList ('"' + $Payload + '" "' + $script + '"') -WindowStyle Hidden -PassThru
            $deadline = (Get-Date).AddSeconds(120)
            while (-not (Test-Path -LiteralPath $report) -and -not $controller.HasExited -and (Get-Date) -lt $deadline) {
                Get-CimInstance Win32_Process -Filter "ParentProcessId = $($controller.Id)" | ForEach-Object {
                    if (-not $children.ContainsKey($_.ProcessId)) {
                        $child = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
                        if ($child) { $null = $child.Handle; $children[$_.ProcessId] = $child }
                    }
                }
                Start-Sleep -Milliseconds 100
            }
            if (-not (Test-Path -LiteralPath $report)) { throw "No scene handoff report: $out ($case)" }
            $result = Get-Content -LiteralPath $report -Raw | ConvertFrom-Json
            if ($case -eq 'startup-failure') {
                if (-not $result.startup_failed) { throw 'Startup failure did not return to setup' }
            } else {
                if (-not $result.ok) { throw 'Process/window changed or setup resources survived the transition' }
                $apps = @($children.Values | Where-Object {$_.ProcessName -eq 'DF3D'})
                if ($apps.Count -ne 1 -or $apps[0].Id -ne $result.pid) { throw 'Expected exactly one Godot process throughout setup and play' }
                if ($case -eq 'app-crash') { $apps[0].Kill() }
                if ($case -eq 'df-crash') {
                    $native = @($children.Values | Where-Object {$_.ProcessName -eq 'Dwarf Fortress'})
                    if ($native.Count -ne 1) { throw 'Expected one owned DF process' }
                    $native[0].Kill()
                }
                if ($case -eq 'controller-crash') { $controller.Kill() }
            }
            if (-not $controller.WaitForExit(15000)) { throw "Controller survived $case" }
            foreach ($child in $children.Values) { if (-not $child.WaitForExit(5000)) { throw "Child $($child.Id) survived $case" } }
        } finally {
            if ($controller) { if (-not $controller.HasExited) { $controller.Kill(); $null=$controller.WaitForExit(10000) }; $controller.Dispose(); $controller=$null }
            foreach ($child in $children.Values) { $null=$child.WaitForExit(5000); $child.Dispose() }
            if (Test-Path -LiteralPath $parkedClient) { Move-Item -LiteralPath $parkedClient -Destination $client }
        }
    }
    Write-Host "SETUP_SESSION_PASS: $out"
} finally {
    try { if ($entered) { Exit-Df3dLane } }
    finally {
        if ($journal) { [DF3D.Release.Package]::Restore($journal) }
        Get-ChildItem Env:DF3D_* | Remove-Item
        foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name, $saved[$name]) }
    }
}
