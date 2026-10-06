# Offline reload regression. Child stand-ins deliberately have non-game names.
param([string]$CaseFilter='*')
$ErrorActionPreference='Stop'
if (@(Get-Process -Name 'Dwarf Fortress' -ErrorAction SilentlyContinue).Count) {
    Write-Output 'QA_INCOMPLETE: close DF before fortress restart tests'; exit 77
}
Import-Module "$PSScriptRoot/Df3dLane.psm1" -Force
Import-Module "$PSScriptRoot/SaveIsolation.psm1" -Force
$lane=Get-Module Df3dLane
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$testRoot=Join-Path $repo ('build/fortress-restart-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$oldTestRoot=$env:DF3D_RESTART_TEST_ROOT
$source=@'
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
using System.Runtime.InteropServices;
class RestartStandin {
 [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)] struct SI {
  public int cb;public string reserved,desktop,title;public int x,y,w,h,xchars,ychars,fill,flags;
  public short show,cb2;public IntPtr reserved2,input,output,error;
 }
 [StructLayout(LayoutKind.Sequential)] struct PI { public IntPtr process,thread;public int pid,tid; }
 [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool CreateProcess(string app,string command,IntPtr pa,IntPtr ta,bool inherit,uint flags,IntPtr env,string cwd,ref SI si,out PI pi);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
 static string root;
 static string Read(string file,string fallback) { var p=Path.Combine(root,file);return File.Exists(p)?File.ReadAllText(p).Trim():fallback; }
 static void Write(string file,string text) { File.WriteAllText(Path.Combine(root,file),text); }
 static int Main(string[] args) {
  if(args.Length==2 && args[0]=="exit-probe") { Thread.Sleep(500);return Int32.Parse(args[1]); }
  root=Environment.GetEnvironmentVariable("DF3D_RESTART_TEST_ROOT");
  string name=Path.GetFileNameWithoutExtension(Process.GetCurrentProcess().MainModule.FileName);
  string scenario=Read("scenario.txt","success");
  if(name.EndsWith("client")) {
   File.AppendAllText(Path.Combine(root,"client-calls.txt"),String.Join(" ",args)+"\n");
   int generation=Int32.Parse(Read("generation.txt","0"));
   if(args[0]=="quit-without-saving") {
    if(scenario=="inprocess-unknown") return 5;
    if(scenario=="inprocess-rejected") return 3;
    Write("at-title.txt","1");return 0;
   }
   if(args[0]=="load") {
    if(scenario.StartsWith("load-exit-")) return Int32.Parse(scenario.Substring(10));
    if(scenario=="load-hang") Thread.Sleep(300000);
    Write("loaded.txt",args[1]);Write("at-title.txt","0");return 0;
   }
   if(scenario=="status-hang" && generation>1) Thread.Sleep(300000);
   int pid=Int32.Parse(Read("df.pid","0"));
   ulong epoch=((ulong)pid<<32)|1;
   bool inprocess=scenario.StartsWith("inprocess");
   bool reloaded=inprocess && File.Exists(Path.Combine(root,"loaded.txt"));
   if(reloaded && scenario!="inprocess-same-epoch") epoch++;
   int phase=scenario=="saving"?6:3;
   if(inprocess && Read("at-title.txt","0")=="1" && scenario!="inprocess-bad-title") { phase=1;epoch=0; }
   int paused=scenario=="unpaused" && generation>1?0:1;
   if(reloaded && scenario=="inprocess-unpaused") paused=0;
   string save=Read("save-id.txt","");
   if(generation>1 && scenario=="wrong-id") save+="-wrong";
   if(reloaded && scenario=="inprocess-wrong-id") save+="-wrong";
   if(generation>1 && scenario=="foreign-epoch") epoch=((ulong)(pid+1)<<32)|1;
   Console.WriteLine("SESSION phase="+phase+" seq=0 result=0 paused="+paused+" year=106 year_tick=100 fort=Test Fort id="+save+" message=Ready with spaces epoch="+epoch);
   return 0;
  }
  if(name.EndsWith("rpc")) {
   File.AppendAllText(Path.Combine(root,"rpc-calls.txt"),String.Join(" ",args)+"\n");
   if(args[0]=="die") {
    try { Process.GetProcessById(Int32.Parse(Read("df.pid","0"))).Kill(); } catch(ArgumentException) {}
    if(scenario=="foreign") {
     string exe=Path.Combine(root,"df3d-restart-standin.exe");
     var si=new SI();si.cb=Marshal.SizeOf(si);PI pi;
     if(!CreateProcess(exe,"\""+exe+"\" foreign",IntPtr.Zero,IntPtr.Zero,false,0x08000000,IntPtr.Zero,root,ref si,out pi)) return 7;
     Write("foreign.pid",pi.pid.ToString());CloseHandle(pi.process);CloseHandle(pi.thread);
    }
   } else Console.WriteLine("mirroring enabled: yes");
   return 0;
  }
  if(args.Length>0 && args[0]=="foreign") { Thread.Sleep(300000);return 0; }
  int gen=Int32.Parse(Read("generation.txt","0"))+1;
  Write("generation.txt",gen.ToString());Write("df.pid",Process.GetCurrentProcess().Id.ToString());
  if(gen>1) {
   if(scenario=="boot-exit") return 0;
   if(scenario=="save-write" || scenario=="current-write") {
    string dir=Path.Combine(root,"save",scenario=="save-write"?"autosave 1":"current");
    Directory.CreateDirectory(dir);File.WriteAllText(Path.Combine(dir,"world.sav"),"unexpected");
   }
  }
  Thread.Sleep(300000);return 0;
 }
}
'@
Add-Type -TypeDefinition $source -OutputAssembly "$testRoot/df3d-restart-standin.exe" -OutputType ConsoleApplication
Copy-Item "$testRoot/df3d-restart-standin.exe" "$testRoot/df3d-restart-client.exe"
Copy-Item "$testRoot/df3d-restart-standin.exe" "$testRoot/df3d-restart-rpc.exe"
# Exercise Restart, Stop, Wait-DfSaveIdle and the actual private-console RPC.
# Substitute only launch and the foreign-process inventory in this module scope.
& $lane {
    function script:Start-Df3d {
        param([string]$DfPath,[switch]$Visible)
        $script:DfVisible=[bool]$Visible
        if ((Get-Content "$script:TestRoot/scenario.txt" -Raw).Trim() -eq 'launch-throw' -and
            (Test-Path "$script:TestRoot/generation.txt")) { throw 'injected launch failure' }
        $p=Start-Process -FilePath "$script:TestRoot/df3d-restart-standin.exe" -WindowStyle Hidden -PassThru
        $script:DfProc=$p
        $deadline=(Get-Date).AddSeconds(5)
        while ((Get-Date) -lt $deadline) {
            if ((Test-Path "$script:TestRoot/df.pid") -and [int](Get-Content "$script:TestRoot/df.pid") -eq $p.Id) { break }
            Start-Sleep -Milliseconds 10
        }
        return $p
    }
    function script:Get-Process {
        param([string]$Name,[int]$Id)
        if ($Name -eq 'Dwarf Fortress' -and (Test-Path "$script:TestRoot/foreign.pid")) {
            return Microsoft.PowerShell.Management\Get-Process -Id ([int](Get-Content "$script:TestRoot/foreign.pid")) -ErrorAction SilentlyContinue
        }
        if ($Name) { return Microsoft.PowerShell.Management\Get-Process -Name $Name -ErrorAction SilentlyContinue }
        return Microsoft.PowerShell.Management\Get-Process -Id $Id
    }
}
function Assert-Case([bool]$Value,[string]$Message) { if (-not $Value) { throw $Message } }
try {
    # A contained child's exit code must survive polling after it exits. This
    # reproduces the real Godot result/ExitCode disagreement under PowerShell 5.1.
    foreach($code in @(0,77)) {
        $child=Start-ContainedProcess -Exe "$testRoot/df3d-restart-standin.exe" -Arguments "exit-probe $code" -WorkingDir $testRoot
        try {
            $deadline=(Get-Date).AddSeconds(5)
            while(-not $child.HasExited -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 20;$child.Refresh()}
            Assert-Case ($child.HasExited -and $null -ne $child.ExitCode -and $child.ExitCode -eq $code) "contained child lost exit code $code"
        } finally { if(-not $child.HasExited){$child.Kill();$child.WaitForExit()};$child.Dispose() }
    }
    # Pure parser/identity cases use an epoch above signed 32 bits and spaced text.
    $state=ConvertFrom-Df3dSessionStatus 'SESSION phase=3 seq=9 result=2 paused=1 year=106 year_tick=5 fort=A Fort id=C:/save/clone name message=Ready with spaces epoch=530239482495'
    Assert-Case ($state.Message -eq 'Ready with spaces' -and $state.SaveId -eq 'C:/save/clone name') 'status parser lost spaces'
    Assert-Case (Test-Df3dReloadIdentity $state 'C:/save/clone name' 123) 'valid identity rejected'
    foreach ($change in @(@{Phase=6},@{Paused=$false},@{SaveId='other'},@{Epoch=[uint64]1})) {
        $bad=$state.Clone();foreach($key in $change.Keys){$bad[$key]=$change[$key]}
        Assert-Case (-not (Test-Df3dReloadIdentity $bad 'C:/save/clone name' 123)) 'invalid identity accepted'
    }
    Assert-Case ($null -eq (ConvertFrom-Df3dSessionStatus 'SESSION phase=3 seq=0 result=0 paused=1 year=1 year_tick=0 fort=x id=y message=z')) 'missing epoch accepted'
    foreach ($case in @('success','no-process','attach','no-lock','smoke','saving','launch-throw','boot-exit',
        'load-exit-1','load-exit-2','load-exit-3','load-exit-4','load-hang','wrong-id','unpaused','foreign-epoch','status-hang','save-write','current-write','foreign',
        'inprocess','inprocess-unknown','inprocess-rejected','inprocess-bad-title','inprocess-same-epoch','inprocess-wrong-id','inprocess-unpaused') | Where-Object { $_ -like $CaseFilter }) {
        $dir=Join-Path $testRoot $case
        New-Item -ItemType Directory -Force "$dir/save/clone name", "$dir/prefs", "$dir/dfhack-config/init" | Out-Null
        foreach($exe in 'standin','client','rpc'){Copy-Item "$testRoot/df3d-restart-$exe.exe" "$dir/df3d-restart-$exe.exe"}
        Set-Content "$dir/scenario.txt" $case
        Set-Content "$dir/save-id.txt" "$dir/save/clone name"
        Set-Content "$dir/save/clone name/world.sav" 'original save'
        Set-Content "$dir/prefs/init.txt" '[SOUND:YES][WINDOWED:NO][MASTER_VOLUME:100]'
        $env:DF3D_RESTART_TEST_ROOT=$dir
        & $lane { param($d) $script:TestRoot=$d } $dir
        $entered=$false;$prior=$null
        try {
            try { Enter-Df3dLane -DfPath $dir; $entered=$true }
            catch { if ($_.Exception.Message -match 'already running') { Write-Output 'QA_INCOMPLETE: lane occupied'; exit 77 }; throw }
            Set-DfPrefs; Install-DfMenuStartup -DfPath $dir
            & $lane {param($d) $script:DfhackRun="$d/df3d-restart-rpc.exe"} $dir
            if ($case -ne 'no-process') { $prior=& $lane { Start-Df3d -DfPath $script:DfPath -Visible } }
            if ($case -eq 'attach') { & $lane { $script:AttachOnly=$true } }
            if ($case -eq 'no-lock') { & $lane { $script:TestMutex=$script:LaneMutex; $script:LaneMutex=$null } }
            if ($case -eq 'smoke') { Set-Content "$dir/dfhack-config/init/dfhackzzz_df3d_smoke.init" 'do not run' }
            $route=if($case.StartsWith('inprocess')){'inprocess'}else{'restart'}
            $r=Restart-Df3dFortress -Route $route -SaveId "$dir/save/clone name" -TimeoutSec 1 -SessionClient "$dir/df3d-restart-client.exe" -SaveRoots @("$dir/save") -EvidenceDir "$dir/evidence"
            $expected=if($case -in @('success','current-write','inprocess')){'ready'}elseif($case -in @('smoke','launch-throw','boot-exit','load-exit-1','load-exit-2','load-exit-3','load-exit-4','load-hang','foreign','inprocess-unknown','inprocess-rejected')){'incomplete'}else{'failed'}
            Assert-Case ($r.Status -eq $expected) "$case expected $expected, got $($r | ConvertTo-Json -Compress)"
            Assert-Case ($null -ne (Get-Command Assert-DfSaveBackupUnchanged -ErrorAction SilentlyContinue)) "$case removed outer-lane save verification command"
            Assert-Case ($r.Route -eq $route -and $r.SaveId -eq "$dir/save/clone name" -and $r.ElapsedSec -ge 0) "$case result contract"
            Assert-Case ($r.Status -eq 'ready' -or $r.Reason.Length -gt 0) "$case missing reason"
            Assert-Case ($r.ElapsedSec -lt 181) "$case elapsed bound exceeded"
            if ($r.Status -eq 'ready') {
                Assert-Case (($r.Pid -eq $r.PreviousPid) -eq ($route -eq 'inprocess') -and $r.Epoch -ne $r.PreviousEpoch -and ($r.Epoch -shr 32) -eq $r.Pid) "$case epoch ownership"
                Assert-Case ((& $lane { $script:DfVisible })) "$case visibility lost"
                Assert-Case (@(Get-Content "$dir/client-calls.txt" | Where-Object {$_ -eq 'status'}).Count -ge 3) 'stop did not use injected client'
            }
            if ($route -eq 'inprocess') {
                $prior.Refresh();Assert-Case (-not $prior.HasExited) "$case stopped the owned process"
                Assert-Case (-not (Test-Path "$dir/rpc-calls.txt")) "$case sent a shutdown RPC"
                $calls=@(Get-Content "$dir/client-calls.txt")
                Assert-Case (@($calls | Where-Object {$_ -eq 'quit-without-saving'}).Count -eq 1) "$case replayed Quit"
                if($case -in @('inprocess-unknown','inprocess-rejected','inprocess-bad-title')) {
                    Assert-Case (@($calls | Where-Object {$_ -like 'load *'}).Count -eq 0) "$case loaded after unverified unload"
                }
            }
            if ($case -in @('attach','no-lock','smoke','saving')) {
                $prior.Refresh();Assert-Case (-not $prior.HasExited) "$case killed original DF"
                Assert-Case (-not (Test-Path "$dir/rpc-calls.txt")) "$case sent an RPC"
            }
            if ($case -eq 'foreign') {
                Assert-Case ($null -ne (Get-Process -Id ([int](Get-Content "$dir/foreign.pid")) -ErrorAction SilentlyContinue)) 'foreign process was killed'
            }
            if ($case -eq 'save-write') { Assert-Case (Test-Path "$dir/evidence/changes.txt") 'save modification evidence missing' }
            if ($case -eq 'no-lock') { & $lane { $script:LaneMutex=$script:TestMutex } }
            Assert-Case ((& $lane { $null -ne $script:LaneMutex })) "$case lost mutex"
            Assert-Case (Test-Path "$dir/prefs/init.txt.df3d-backup") "$case lost prefs backup"
            Assert-Case (Test-Path "$dir/dfhack-config/init/dfhackzzz_df3d_menu.init") "$case lost menu staging"
            Write-Output "restart case $case PASS ($([Math]::Round($r.ElapsedSec,2))s)"
        } finally {
            if ($case -eq 'no-lock') { & $lane { if (-not $script:LaneMutex) { $script:LaneMutex=$script:TestMutex } } }
            # Stop only the recorded stand-in PIDs, even for refused/saving tests.
            foreach($pidFile in @("$dir/df.pid","$dir/foreign.pid")) {
                if (Test-Path $pidFile) { Stop-Process -Id ([int](Get-Content $pidFile)) -Force -ErrorAction SilentlyContinue }
            }
            & $lane { $script:AttachOnly=$false }
            if ($entered) { Exit-Df3dLane }
        }
    }
    Write-Output 'fortress restart PASS'
} finally { $env:DF3D_RESTART_TEST_ROOT=$oldTestRoot }
