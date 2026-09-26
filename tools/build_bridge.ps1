# Builds the DFHack fork (with the df3d plugin) and installs it into the DF
# Steam directory. Follows DFHack's own build/win64 conventions
# (generate-MSVC-minimal.bat / build-release.bat / install-release.bat).
#
# The INSTALL target copies DFHack directly into the DF dir (additive:
# dfhooks.dll, dfhooks_dfhack.ini, hack\, dfhack-run.exe, ...). To remove:
# delete those files/dirs - DF's own files are not modified.
#
# Release config only: Debug is not ABI-compatible with DF (Compile.rst).
param(
    [string]$DfPath,
    [string]$Config = "Release",
    [switch]$SkipInstall
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
Import-Module (Join-Path $PSScriptRoot 'SteamPaths.psm1') -Force
if ($SkipInstall) {
    # Build-only checks do not require an installed game.
    if (-not $DfPath) { $DfPath = $env:DF3D_DF_PATH }
    if (-not $DfPath) { $DfPath = Join-Path $repo 'build\dfhack-stage' }
    $DfPath = [IO.Path]::GetFullPath($DfPath)
} else {
    $DfPath = Resolve-Df3dDfPath -DfPath $DfPath
}
$dfhackSrc = Join-Path $repo "external\dfhack"
$buildDir = Join-Path $dfhackSrc "build\VC2022"

if (-not (Test-Path (Join-Path $dfhackSrc "CMakeLists.txt"))) {
    throw "DFHack tree not found at $dfhackSrc"
}

# df-structures codegen needs perl (Strawberry) on PATH at configure time.
# A perl on PATH without XML::LibXML (MSYS2, Git) must not shadow Strawberry.
$perlOk = $false
if (Get-Command perl -ErrorAction SilentlyContinue) {
    & cmd.exe /c "perl -MXML::LibXML -e 1 >nul 2>&1"
    $perlOk = ($LASTEXITCODE -eq 0)
}
if (-not $perlOk) {
    $strawberry = "C:\Strawberry\perl\bin"
    if (Test-Path "$strawberry\perl.exe") {
        $env:Path = "$strawberry;C:\Strawberry\c\bin;$env:Path"
        Write-Host "[build] added Strawberry Perl to PATH"
    } else {
        throw "perl not found (Strawberry Perl required for df-structures codegen)"
    }
}
perl -MXML::LibXML -e "1" ; if ($LASTEXITCODE -ne 0) { throw "perl XML::LibXML missing" }

Write-Host "[build] configuring (VS 17 2022, x64, install -> $DfPath)"
cmake -S $dfhackSrc -B $buildDir -G "Visual Studio 17 2022" -A x64 `
    -DCMAKE_INSTALL_PREFIX="$DfPath" `
    -DBUILD_DEV_PLUGINS=0 -DBUILD_STONESENSE=0 -DBUILD_DOCS=0 -DBUILD_TESTS=0
if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }

Write-Host "[build] building ($Config) - this takes a while on first build"
cmake --build $buildDir -t ALL_BUILD --config $Config -- /m
if ($LASTEXITCODE -ne 0) { throw "build failed" }

if (-not $SkipInstall) {
    if (@(Get-Process "Dwarf Fortress" -ErrorAction SilentlyContinue).Count) {
        throw "Refusing install while Dwarf Fortress is running. Close it and retry."
    }
    Write-Host "[build] installing into $DfPath"
    cmake --build $buildDir -t INSTALL --config $Config
    if ($LASTEXITCODE -ne 0) { throw "install failed" }
    foreach ($p in @("dfhooks.dll", "hack\plugins\df3d.plug.dll", "hack\dfhack-run.exe")) {
        if (-not (Test-Path (Join-Path $DfPath $p))) { throw "install verification failed: missing $p" }
    }
    Write-Host "[build] install verified (dfhooks.dll, df3d.plug.dll, dfhack-run.exe present)"
}
Write-Host "[build] done"
