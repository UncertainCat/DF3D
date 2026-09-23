# Run with Windows PowerShell 5.1: powershell -File tools/smoke/attach_lifecycle_test.ps1
# Real launcher/Job Object lifecycle with disposable stand-ins; no game is opened.
$ErrorActionPreference = 'Stop'
# A running DF is a missing prerequisite, not a defect: verify.py maps exit 77 plus
# a QA_INCOMPLETE line to incomplete rather than failed.
if (@(Get-Process 'Dwarf Fortress' -ErrorAction SilentlyContinue).Count) { Write-Output 'QA_INCOMPLETE: Dwarf Fortress is running; close it before the isolated attach lifecycle test'; exit 77 }
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$dir = Join-Path $repo ('build\attach-test-' + [guid]::NewGuid().ToString('N'))
try {
New-Item -ItemType Directory -Force "$dir\hack", "$dir\prefs", "$dir\dfhack-config\init" | Out-Null
Set-Content "$dir\prefs\init.txt" 'untouched preferences'
Set-Content "$dir\dfhack-config\init\sentinel.init" 'untouched init'
$source = @"
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
class Mock {
 static void Main() {
  string exe=Path.GetFileNameWithoutExtension(Process.GetCurrentProcess().MainModule.FileName);
  if(exe=="dfhack-run") { Console.WriteLine("mirroring enabled: yes\nmap loaded: no\nterrain grid: unmapped"); return; }
  if(exe=="viewer") { File.WriteAllText(Environment.GetEnvironmentVariable("ATTACH_TEST_PID"), Process.GetCurrentProcess().Id.ToString()); if(Environment.GetEnvironmentVariable("ATTACH_TEST_WAIT")!="1") { Thread.Sleep(1000); return; } }
  Thread.Sleep(300000);
 }
}
"@
Add-Type -TypeDefinition $source -OutputAssembly "$dir\Dwarf Fortress.exe" -OutputType ConsoleApplication
Copy-Item "$dir\Dwarf Fortress.exe" "$dir\hack\dfhack-run.exe"
Copy-Item "$dir\Dwarf Fortress.exe" "$dir\viewer.exe"
$external = Start-Process -FilePath "$dir\Dwarf Fortress.exe" -WindowStyle Hidden -PassThru
} catch { if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }; throw }
try {
 foreach ($abrupt in @($false, $true)) {
  $env:ATTACH_TEST_WAIT = if ($abrupt) { '1' } else { '0' }
  $env:ATTACH_TEST_PID = "$dir\viewer-$abrupt.pid"
  $argsText = '-NoProfile -ExecutionPolicy Bypass -File "{0}\play_live.ps1" -Attach -DfPath "{1}" -GodotExe "{1}\viewer.exe" -DfProcessId {2}' -f $PSScriptRoot, $dir, $external.Id
  $launcher = Start-Process powershell -ArgumentList $argsText -WindowStyle Hidden -PassThru -RedirectStandardOutput "$dir\launcher-$abrupt.log" -RedirectStandardError "$dir\launcher-$abrupt.err"
  try {
   $deadline=(Get-Date).AddSeconds(30)
   while (-not (Test-Path $env:ATTACH_TEST_PID) -and -not $launcher.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 100; $launcher.Refresh() }
   if (-not (Test-Path $env:ATTACH_TEST_PID)) { throw "Viewer did not start: $(Get-Content $dir\launcher-$abrupt.log)" }
   $viewerId=[int](Get-Content $env:ATTACH_TEST_PID)
   if ($abrupt) { Stop-Process -Id $launcher.Id -Force }
   if (-not $launcher.WaitForExit(15000)) { throw 'Launcher failed to exit' }
   if (-not $abrupt -and -not (Select-String -Path "$dir\launcher-$abrupt.log" -SimpleMatch "[play] done")) { throw "Launcher failed: $(Get-Content $dir\launcher-$abrupt.log)" }
   Start-Sleep -Milliseconds 300
   $external.Refresh()
   if ($external.HasExited) { throw 'Attach terminated external DF' }
   if (Get-Process -Id $viewerId -ErrorAction SilentlyContinue) { throw 'Viewer escaped containment' }
   if ((Get-Content "$dir\prefs\init.txt") -ne 'untouched preferences') { throw 'Attach changed preferences' }
   if (@(Get-ChildItem "$dir\dfhack-config\init").Count -ne 1 -or (Get-Content "$dir\dfhack-config\init\sentinel.init") -ne 'untouched init') { throw 'Attach changed init files' }
   if (Test-Path "$dir\prefs\init.txt.df3d-backup") { throw 'Attach staged preferences' }
   Write-Host "attach lifecycle PASS: abrupt=$abrupt, external pid=$($external.Id) preserved, viewer terminated, prefs/init unchanged"
  } finally { if (-not $launcher.HasExited) { Stop-Process -Id $launcher.Id -Force } }
 }
} finally {
 if (-not $external.HasExited) { Stop-Process -Id $external.Id -Force }
 Remove-Item Env:ATTACH_TEST_WAIT, Env:ATTACH_TEST_PID -ErrorAction SilentlyContinue
 # Stand-in binaries may stay locked briefly after their processes die.
 for ($attempt = 0; $attempt -lt 10 -and (Test-Path -LiteralPath $dir); $attempt++) {
  try { Remove-Item -LiteralPath $dir -Recurse -Force -Confirm:$false -ErrorAction Stop } catch { Start-Sleep -Milliseconds 500 }
 }
 if (Test-Path -LiteralPath $dir) { Write-Warning "Could not remove temporary directory $dir" }
}
