# Back up all save roots before a contained lane exercises any native save.
# A cloned fortress alone does not isolate DF's shared autosave slots.
Set-StrictMode -Version 2

function New-DfSaveBackup {
    param(
        [Parameter(Mandatory)][string[]]$SaveRoots,
        [Parameter(Mandatory)][string]$BackupRoot,
        [string[]]$AllowedDirectories = @('current')
    )
    $ErrorActionPreference = 'Stop'
    $destination = [IO.Path]::GetFullPath($BackupRoot)
    if (Test-Path -LiteralPath $destination) { throw 'Save backup destination already exists' }
    $roots = @($SaveRoots | ForEach-Object { (Resolve-Path -LiteralPath $_).Path.TrimEnd('\', '/') })
    foreach ($root in $roots) {
        if ($destination.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $destination -eq $root) {
            throw 'Save backup must be outside every source save root'
        }
    }
    foreach ($name in $AllowedDirectories) {
        if ([string]::IsNullOrWhiteSpace($name) -or $name -in @('.', '..') -or $name.IndexOfAny([char[]]'\/:') -ge 0) {
            throw 'Allowed save directories must be exact directory names'
        }
    }
    New-Item -ItemType Directory -Path $destination | Out-Null
    $records = @()
    for ($i = 0; $i -lt $roots.Count; $i++) {
        $copy = Join-Path $destination "root-$i"
        Copy-Item -LiteralPath $roots[$i] -Destination $copy -Recurse
        foreach ($file in Get-ChildItem -LiteralPath $roots[$i] -File -Recurse) {
            $relative = $file.FullName.Substring($roots[$i].Length).TrimStart('\', '/')
            $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
            if ($hash -ne (Get-FileHash -LiteralPath (Join-Path $copy $relative) -Algorithm SHA256).Hash) {
                throw "Save backup verification failed: $relative"
            }
            $records += [pscustomobject]@{ Root = $i; Path = $relative; Hash = $hash }
        }
    }
    $manifest = [pscustomobject]@{ Roots = $roots; Backup = $destination; AllowedDirectories = $AllowedDirectories; Files = $records }
    $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $destination 'manifest.json') -Encoding UTF8
    return $manifest
}

function Assert-DfSaveBackupUnchanged {
    param([Parameter(Mandatory)]$Manifest)
    $ErrorActionPreference = 'Stop'
    $expected = @{}
    foreach ($entry in $Manifest.Files) {
        $directory = ($entry.Path -split '[\\/]')[0]
        if ($directory -in $Manifest.AllowedDirectories) { continue }
        $expected["$($entry.Root)/$($entry.Path)"] = $entry.Hash
    }
    $changes = @()
    for ($i = 0; $i -lt $Manifest.Roots.Count; $i++) {
        $root = $Manifest.Roots[$i]
        foreach ($file in Get-ChildItem -LiteralPath $root -File -Recurse) {
            $relative = $file.FullName.Substring($root.Length).TrimStart('\', '/')
            if (($relative -split '[\\/]')[0] -in $Manifest.AllowedDirectories) { continue }
            $key = "$i/$relative"
            if (-not $expected.ContainsKey($key)) { $changes += "added $key"; continue }
            if ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash -ne $expected[$key]) { $changes += "changed $key" }
            $expected.Remove($key)
        }
    }
    foreach ($key in $expected.Keys) { $changes += "missing $key" }
    if ($changes.Count) {
        $changes | Set-Content -LiteralPath (Join-Path $Manifest.Backup 'changes.txt') -Encoding UTF8
        throw "Non-test saves changed. Verified backups and changes.txt retained at $($Manifest.Backup)"
    }
    Write-Output 'Non-test save files unchanged; verified backups retained.'
}

Export-ModuleMember -Function New-DfSaveBackup, Assert-DfSaveBackupUnchanged
