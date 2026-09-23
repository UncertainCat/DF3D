# Read-only attachment to an already running DF. No input, prefs, save or process changes.
param([Parameter(Mandatory)][string]$Output,
 [string]$DfPath=$(if ($env:DF3D_DF_PATH) { $env:DF3D_DF_PATH } else { 'C:\Program Files (x86)\Steam\steamapps\common\Dwarf Fortress' }),
 [int]$Port=5010)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Df3dLane.psm1') -Force
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$target=[IO.Path]::GetFullPath($Output)
$allowed=[IO.Path]::GetFullPath((Join-Path $repo 'build'))+[IO.Path]::DirectorySeparatorChar
if (-not $target.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase)) { throw 'Raw widget observations must remain under ignored build/.' }
if (Test-Path -LiteralPath $target) { throw 'Use a new capture filename; existing observations are preserved.' }
if (@(Get-Process 'Dwarf Fortress' -ErrorAction SilentlyContinue).Count -ne 1) { throw 'Exactly one running DF is required for read-only capture.' }
$scriptPath=(Join-Path $repo 'tools/ui_bake/capture_widgets.lua').Replace('\','/')
$target=$target.Replace('\','/')
if ($target.Contains(']]')) { throw 'Unsupported output path' }
try {
 Enter-Df3dLane -DfPath $DfPath -Port $Port -AttachOnly
 $result=Invoke-DfhackRaw @('lua',"assert(loadfile([[$scriptPath]]))([[$target]])")
 $result.Output
 if ($result.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $target)) { throw 'Widget capture failed' }
} finally { Exit-Df3dLane }
