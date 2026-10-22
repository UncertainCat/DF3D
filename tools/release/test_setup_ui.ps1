param([Parameter(Mandatory=$true)][string]$Payload, [Parameter(Mandatory=$true)][string]$Game)
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$Payload = (Resolve-Path -LiteralPath $Payload).Path
$Game = (Resolve-Path -LiteralPath $Game).Path
$buildRoot = [IO.Path]::GetFullPath((Join-Path $repo 'build')) + '\'
if (-not $Game.StartsWith($buildRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Use a disposable game copy under build.' }
$out = Join-Path $repo ('build\setup-ui-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $out | Out-Null
$exe = Join-Path $out 'test.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /platform:x64 /main:SetupUiTests "/out:$exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll /reference:System.IO.Compression.dll /reference:System.IO.Compression.FileSystem.dll (Join-Path $PSScriptRoot 'Launcher.cs') (Join-Path $PSScriptRoot 'SetupUiTests.cs')
if ($LASTEXITCODE) { throw 'UI test runner compilation failed' }
$oldLocal = $env:LOCALAPPDATA
$oldRoaming = $env:APPDATA
$env:LOCALAPPDATA = Join-Path $out 'Local'
$env:APPDATA = Join-Path $out 'Roaming'
$env:DF3D_SETUP_GAME = $Game
$env:DF3D_DF_PATH = $Game
$env:DF3D_CACHE_DIR = Join-Path $out 'assets'
$env:DF3D_SETUP_REPORT = Join-Path $out 'first.txt'
$script = Join-Path $repo 'presentations\godot\project\tests\setup_launcher_test.gd'
try {
    foreach ($pass in @('first', 'reopen')) {
        $env:DF3D_SETUP_REOPEN = if ($pass -eq 'reopen') { '1' } else { '0' }
        $env:DF3D_SETUP_REPORT = Join-Path $out ($pass + '.txt')
        $process = Start-Process -FilePath $exe -ArgumentList ('"' + $Payload + '" "' + $script + '"') -WindowStyle Hidden -PassThru
        if (-not $process.WaitForExit(180000)) { $process.Kill(); throw "UI integration timed out: $out" }
        if (-not (Test-Path -LiteralPath $env:DF3D_SETUP_REPORT) -or (Get-Content -LiteralPath $env:DF3D_SETUP_REPORT -Raw) -ne 'PASS') { throw "UI integration failed: $out" }
    }
    Write-Host "SETUP_UI_PASS: $out"
} finally {
    [Reflection.Assembly]::LoadFrom($exe) | Out-Null
    $backups = Join-Path $env:LOCALAPPDATA 'DF3D\backups'
    if (Test-Path -LiteralPath $backups) {
        Get-ChildItem -LiteralPath $backups -Filter transaction.json -Recurse | ForEach-Object { [DF3D.Release.Package]::Restore($_.FullName) }
    }
    $env:LOCALAPPDATA = $oldLocal
    $env:APPDATA = $oldRoaming
}
