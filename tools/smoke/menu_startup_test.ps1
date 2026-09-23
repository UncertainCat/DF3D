# Disposable stand-ins prove title-only owned startup and cleanup without DF.
$ErrorActionPreference = 'Stop'
if (@(Get-Process 'Dwarf Fortress' -ErrorAction SilentlyContinue).Count) { throw 'DF must be closed before this isolated test' }
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dir = Join-Path $repo ('build\menu-startup-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force "$dir\hack", "$dir\prefs", "$dir\dfhack-config\init" | Out-Null
Set-Content "$dir\prefs\init.txt" '[SOUND:YES][WINDOWED:NO][MASTER_VOLUME:100]'
Set-Content "$dir\dfhack-config\init\sentinel.init" 'preserve'
# Simulate a prior force-closed launcher; the exact owned file is recoverable.
Set-Content "$dir\dfhack-config\init\dfhackzzz_df3d_menu.init" 'enable df3d'
$source = @'
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
class Mock {
 static void Main(string[] args) {
  string root=Environment.GetEnvironmentVariable("MENU_STARTUP_TEST_ROOT");
  string exe=Path.GetFileNameWithoutExtension(Process.GetCurrentProcess().MainModule.FileName);
  if(exe=="dfhack-run") {
   File.AppendAllText(Path.Combine(root,"commands.txt"),String.Join(" ",args)+"\n");
   if(args.Length>0 && args[0]=="die") {
    var pidFile=Path.Combine(root,"df.pid");
    if(File.Exists(pidFile)) try { Process.GetProcessById(Int32.Parse(File.ReadAllText(pidFile))).Kill(); } catch(ArgumentException) {}
   } else Console.WriteLine("mirroring enabled: yes\nmap loaded: no\nterrain grid: unmapped");
   return;
  }
  if(exe=="viewer") {
   string init=File.ReadAllText(Path.Combine(root,"dfhack-config","init","dfhackzzz_df3d_menu.init")).Trim();
   File.WriteAllText(Path.Combine(root,"viewer.txt"),init);
   Thread.Sleep(500); return;
  }
  File.WriteAllText(Path.Combine(root,"df.pid"),Process.GetCurrentProcess().Id.ToString());
  Thread.Sleep(300000);
 }
}
'@
Add-Type -TypeDefinition $source -OutputAssembly "$dir\Dwarf Fortress.exe" -OutputType ConsoleApplication
Copy-Item "$dir\Dwarf Fortress.exe" "$dir\hack\dfhack-run.exe"
Copy-Item "$dir\Dwarf Fortress.exe" "$dir\viewer.exe"
$env:MENU_STARTUP_TEST_ROOT = $dir
try {
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\play_live.ps1" -DfPath $dir -GodotExe "$dir\viewer.exe" -Silent -BootTimeoutSec 15
    if ($LASTEXITCODE -ne 0) { throw 'Owned menu launcher failed' }
    if ((Get-Content "$dir\viewer.txt") -ne 'enable df3d') { throw 'Startup did not enable only the bridge' }
    $commands = @(Get-Content "$dir\commands.txt")
    if (@($commands | Where-Object { $_ -notin @('df3d status','die') }).Count) { throw "Unexpected auto-load/unpause command: $commands" }
    if ((Get-Content "$dir\prefs\init.txt") -ne '[SOUND:YES][WINDOWED:NO][MASTER_VOLUME:100]') { throw 'Preferences not restored' }
    if (@(Get-ChildItem "$dir\dfhack-config\init").Count -ne 1 -or (Get-Content "$dir\dfhack-config\init\sentinel.init") -ne 'preserve') { throw 'Startup files not restored' }
    $ownedId = [int](Get-Content "$dir\df.pid")
    if (Get-Process -Id $ownedId -ErrorAction SilentlyContinue) { throw 'Owned DF survived viewer exit' }
    Write-Host 'menu startup PASS: title-only bridge, no automatic load/unpause, owned cleanup and preferences restored'
} finally {
    Remove-Item Env:MENU_STARTUP_TEST_ROOT -ErrorAction SilentlyContinue
}
