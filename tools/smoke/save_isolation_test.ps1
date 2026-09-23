# Offline regression for SaveIsolation.psm1 backup/verification; uses temp dirs only.
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'SaveIsolation.psm1') -Force
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$testRoot = Join-Path $repo ('build\save-isolation-test-' + [guid]::NewGuid().ToString('N'))
$source = Join-Path $testRoot 'saves'
New-Item -ItemType Directory -Path (Join-Path $source 'original'), (Join-Path $source 'test-fort') -Force | Out-Null
Set-Content -LiteralPath (Join-Path $source 'original\world.sav') -Value 'original-state'
Set-Content -LiteralPath (Join-Path $source 'test-fort\world.sav') -Value 'test-state'
$manifest = New-DfSaveBackup -SaveRoots @($source) -BackupRoot (Join-Path $testRoot 'backup') -AllowedDirectories @('test-fort')
Set-Content -LiteralPath (Join-Path $source 'test-fort\world.sav') -Value 'test-save-changed'
Assert-DfSaveBackupUnchanged -Manifest $manifest
Set-Content -LiteralPath (Join-Path $source 'original\world.sav') -Value 'unexpected-change'
$caught = $false
try { Assert-DfSaveBackupUnchanged -Manifest $manifest } catch { $caught = $true }
if (-not $caught) { throw 'Missed original save mutation' }
Copy-Item -LiteralPath (Join-Path $manifest.Backup 'root-0\original\world.sav') -Destination (Join-Path $source 'original\world.sav') -Force
Set-Content -LiteralPath (Join-Path $source 'original\new.dat') -Value 'unexpected-addition'
$caught = $false
try { Assert-DfSaveBackupUnchanged -Manifest $manifest } catch { $caught = $true }
if (-not $caught) { throw 'Missed added original save file' }
if ((Get-Content -LiteralPath (Join-Path $manifest.Backup 'root-0\original\world.sav')) -ne 'original-state') { throw 'Backup was changed' }
Write-Output 'Save isolation tests: PASS'
