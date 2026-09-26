# Shared Windows PowerShell 5.1-compatible discovery for build and play.
function Read-SteamKeyValues {
    param([string]$Path)
    $tokens = [regex]::Matches([IO.File]::ReadAllText($Path), '//[^\r\n]*|"(?:\\.|[^"\\])*"|[{}]|[^\s{}"]+')
    $root = @{}
    $stack = New-Object System.Collections.Stack
    $stack.Push($root)
    $key = $null
    foreach ($token in $tokens) {
        $value = $token.Value
        if ($value.StartsWith('//')) { continue }
        if ($value -eq '{') {
            if ($null -eq $key) { throw "Invalid Steam metadata: $Path" }
            $child = @{}
            $stack.Peek()[$key] = $child
            $stack.Push($child)
            $key = $null
        } elseif ($value -eq '}') {
            if ($stack.Count -le 1 -or $null -ne $key) { throw "Invalid Steam metadata: $Path" }
            $null = $stack.Pop()
        } else {
            if ($value.StartsWith('"')) {
                $value = $value.Substring(1, $value.Length - 2).Replace('\\', '\').Replace('\"', '"')
            }
            if ($null -eq $key) { $key = $value }
            else { $stack.Peek()[$key] = $value; $key = $null }
        }
    }
    if ($stack.Count -ne 1 -or $null -ne $key) { throw "Invalid Steam metadata: $Path" }
    return $root
}

function Get-Df3dSteamRoots {
    # An explicit root is exclusive, making discovery reproducible in tests.
    if ($env:DF3D_STEAM_ROOT) { return $env:DF3D_STEAM_ROOT }
    foreach ($entry in @(
        @('HKCU:\Software\Valve\Steam', 'SteamPath'),
        @('HKLM:\Software\Valve\Steam', 'InstallPath'),
        @('HKLM:\Software\WOW6432Node\Valve\Steam', 'InstallPath')
    )) {
        $item = Get-ItemProperty -LiteralPath $entry[0] -ErrorAction SilentlyContinue
        if ($item -and $item.($entry[1])) { $item.($entry[1]) }
    }
    if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Steam' }
}

function Resolve-Df3dSteamExecutable {
    param([string]$AppId, [string]$Executable, [string]$Override, [string]$Hint)
    if ($Override) {
        $path = [IO.Path]::GetFullPath($Override)
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Executable not found: $path. Check $Hint; an explicit override is never silently replaced."
        }
        return $path
    }
    $searched = New-Object System.Collections.Generic.List[string]
    foreach ($root in @(Get-Df3dSteamRoots | Select-Object -Unique)) {
        $libraries = @($root)
        $folders = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $folders) {
            try {
                $vdf = Read-SteamKeyValues $folders
                if ($vdf.libraryfolders -is [hashtable]) {
                    foreach ($entry in $vdf.libraryfolders.GetEnumerator() | Sort-Object Name) {
                        if ($entry.Name -notmatch '^\d+$') { continue }
                        if ($entry.Value -is [hashtable]) { $libraries += $entry.Value.path }
                        else { $libraries += $entry.Value } # Older Steam format.
                    }
                }
            } catch { $searched.Add("${folders}: $($_.Exception.Message)") }
        }
        foreach ($library in @($libraries | Where-Object { $_ } | Select-Object -Unique)) {
            $manifest = Join-Path $library "steamapps\appmanifest_$AppId.acf"
            $searched.Add($manifest)
            if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { continue }
            try { $app = (Read-SteamKeyValues $manifest).AppState }
            catch { continue }
            if (-not $app -or $app.appid -ne $AppId -or -not $app.installdir) { continue }
            $path = Join-Path (Join-Path (Join-Path $library 'steamapps\common') $app.installdir) $Executable
            if (Test-Path -LiteralPath $path -PathType Leaf) { return [IO.Path]::GetFullPath($path) }
        }
    }
    throw "Steam app $AppId ($Executable) was not found. Install it through Steam or set $Hint. Searched: $($searched -join '; ')"
}

function Resolve-Df3dDfPath {
    param([string]$DfPath)
    if (-not $DfPath) { $DfPath = $env:DF3D_DF_PATH }
    $override = if ($DfPath) { Join-Path $DfPath 'Dwarf Fortress.exe' } else { '' }
    $exe = Resolve-Df3dSteamExecutable -AppId '975370' -Executable 'Dwarf Fortress.exe' -Override $override -Hint '-DfPath / DF3D_DF_PATH'
    return Split-Path $exe -Parent
}

function Resolve-Df3dGodotExe {
    param([string]$GodotExe)
    if (-not $GodotExe) { $GodotExe = $env:DF3D_GODOT }
    Resolve-Df3dSteamExecutable -AppId '404790' -Executable 'godot.windows.opt.tools.64.exe' -Override $GodotExe -Hint '-GodotExe / DF3D_GODOT'
}

Export-ModuleMember -Function Resolve-Df3dDfPath, Resolve-Df3dGodotExe
