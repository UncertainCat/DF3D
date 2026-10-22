using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Runtime.InteropServices;
using System.Text;
using DF3D.Release;

// Stand-ins only: never launches or searches for the real game.
public static class LifecycleTests {
 [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
 [DllImport("user32.dll")] static extern IntPtr GetThreadDesktop(uint thread);
 [DllImport("user32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern bool GetUserObjectInformation(IntPtr handle,int index,StringBuilder name,int length,out int needed);
 static string DesktopName(){var name=new StringBuilder(256);int needed;if(!GetUserObjectInformation(GetThreadDesktop(GetCurrentThreadId()),2,name,512,out needed))throw new System.ComponentModel.Win32Exception();return name.ToString();}
 static string Self { get { return typeof(LifecycleTests).Assembly.Location; } }
 static ProcessStartInfo Info(string args) { return new ProcessStartInfo(Self,args) {UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Path.GetDirectoryName(Self)}; }
 static void Require(bool value,string message) {if(!value)throw new Exception(message);}
 static void Stop(Process p) {if(p==null)return;try{if(!p.HasExited)p.Kill();p.WaitForExit(5000);}finally{p.Dispose();}}
 static void WaitForFile(string path) {var end=DateTime.UtcNow.AddSeconds(10);while(!File.Exists(path)&&DateTime.UtcNow<end)Thread.Sleep(20);Require(File.Exists(path),"Missing child report: "+path);}
 static void ExitCases(string directory) {
  for(int which=0;which<2;which++)for(int crash=0;crash<2;crash++) {
   string signal=Path.Combine(directory,"exit-"+which+"-"+crash);
   Process controller=null,app=null,game=null;
   try {
    controller=Process.Start(Info("--session-owner \""+signal+"\""));WaitForFile(signal);
    var ids=File.ReadAllText(signal).Split(',');app=Process.GetProcessById(int.Parse(ids[0]));game=Process.GetProcessById(int.Parse(ids[1]));var h1=app.Handle;var h2=game.Handle;
    if(crash==1)(which==0?app:game).Kill();else File.WriteAllText(signal+"."+(which==0?app:game).Id,"exit");
    Require(controller.WaitForExit(10000)&&app.WaitForExit(5000)&&game.WaitForExit(5000),"Either app or DF exit must clean the whole session, including controller");
   }finally{Stop(controller);Stop(app);Stop(game);}
  }
 }
 static void TreeCases(string directory) {
  for(int crash=0;crash<2;crash++) {
   string report=Path.Combine(directory,"tree-"+crash);
   Process owner=null,host=null,helper=null,grandchild=null;
   try {
    owner=Process.Start(Info("--tree-owner \""+report+"\""));WaitForFile(report);WaitForFile(report+".branch");
    var ids=File.ReadAllText(report).Split(',');
    host=Process.GetProcessById(int.Parse(ids[0]));helper=Process.GetProcessById(int.Parse(ids[1]));grandchild=Process.GetProcessById(int.Parse(File.ReadAllText(report+".branch")));
    var h1=host.Handle;var h2=helper.Handle;var h3=grandchild.Handle;
    if(crash==1)owner.Kill();else File.WriteAllText(report+".exit","exit");
    Require(owner.WaitForExit(5000)&&host.WaitForExit(5000)&&helper.WaitForExit(5000)&&grandchild.WaitForExit(5000),"Launcher exit must clean nested jobs, direct helpers and grandchildren");
   }finally{Stop(owner);Stop(host);Stop(helper);Stop(grandchild);}
  }
 }
 [STAThread] public static int Main(string[] args) {
  if(args[0]=="--session-owner") {
   OwnedSession.ContainLauncher();
   using(var appJob=new OwnedSession())using(var gameJob=new OwnedSession())using(var app=appJob.Start(Info("--exit-on-file \""+args[1]+"\"")))using(var game=gameJob.Start(Info("--exit-on-file \""+args[1]+"\""),true)) {
    File.WriteAllText(args[1],app.Id+","+game.Id);while(!app.HasExited&&!game.HasExited)Thread.Sleep(20);
   }return 0;
  }
  if(args[0]=="--exit-on-file") {var end=DateTime.UtcNow.AddSeconds(30);while(!File.Exists(args[1]+"."+Process.GetCurrentProcess().Id)&&DateTime.UtcNow<end)Thread.Sleep(20);return 0;}
  if(args[0]=="--branch") {using(var child=Process.Start(Info("--worker"))){File.WriteAllText(args[1],child.Id.ToString());Thread.Sleep(60000);}return 0;}
  if(args[0]=="--tree-owner") {
   OwnedSession.ContainLauncher();
   using(var session=new OwnedSession())using(var host=session.Start(Info("--worker"),true))using(var helper=Process.Start(Info("--branch \""+args[1]+".branch\""))) {
    File.WriteAllText(args[1],host.Id+","+helper.Id);WaitForFile(args[1]+".exit");
   }return 0;
  }
  if(args[0]=="--desktop") {File.WriteAllText(args[1],DesktopName());Thread.Sleep(60000);return 0;}
  if(args[0]=="--worker") {Thread.Sleep(60000);return 0;}
  if(args[0]=="--owner") {
   using(var session=new OwnedSession())using(var child=session.Start(Info("--worker"))) {
    File.WriteAllText(args[1],child.Id.ToString());Thread.Sleep(60000);
   }
   return 0;
  }
  Process unrelated=null,first=null,second=null,owner=null,orphan=null;
  try {
   IntegrationTests.Run(Path.GetDirectoryName(args[1]));
   unrelated=Process.Start(Info("--worker"));
   ExitCases(Path.GetDirectoryName(args[1]));
   TreeCases(Path.GetDirectoryName(args[1]));
   using(var session=new OwnedSession()) {
    string hiddenReport=args[1]+".hidden",visibleReport=args[1]+".visible";
    first=session.Start(Info("--desktop \""+hiddenReport+"\""),true);second=session.Start(Info("--desktop \""+visibleReport+"\""));
    var desktopDeadline=DateTime.UtcNow.AddSeconds(10);
    while((!File.Exists(hiddenReport)||!File.Exists(visibleReport))&&DateTime.UtcNow<desktopDeadline)Thread.Sleep(20);
    Require(File.ReadAllText(hiddenReport).StartsWith("df3d_"),"Native host must start on a private desktop");
    Require(File.ReadAllText(visibleReport)==DesktopName(),"Viewer must remain on the user's desktop");
    Require(!first.HasExited&&!second.HasExited,"Children must run before cleanup");
    session.Dispose();session.Dispose();
    Require(first.WaitForExit(5000)&&second.WaitForExit(5000),"Both children must exit when the session closes");
    bool refused=false;try{session.Start(Info("--worker"));}catch(ObjectDisposedException){refused=true;}
    Require(refused,"Disposed ownership must reject launch");
   }
   first.Dispose();first=null;second.Dispose();second=null;
   try {
    using(var session=new OwnedSession()) {
     first=session.Start(Info("--worker"));
     var missing=Info("");missing.FileName=Path.Combine(Path.GetDirectoryName(Self),"missing-child.exe");
     session.Start(missing);
     throw new Exception("Missing executable accepted");
    }
   }catch(System.ComponentModel.Win32Exception){}
   Require(first.WaitForExit(5000),"Startup failure must clean an already started child");
   string marker=args[1]+".pid";
   owner=Process.Start(Info("--owner \""+marker+"\""));
   var deadline=DateTime.UtcNow.AddSeconds(10);
   while(!File.Exists(marker)&&!owner.HasExited&&DateTime.UtcNow<deadline)Thread.Sleep(20);
   Require(File.Exists(marker),"Owner did not report its child");
   orphan=Process.GetProcessById(int.Parse(File.ReadAllText(marker)));var held=orphan.Handle;
   owner.Kill();Require(owner.WaitForExit(5000)&&orphan.WaitForExit(5000),"Owner crash must clean its child");
   Require(!unrelated.HasExited,"Unrelated processes must survive all cleanup paths");
   File.WriteAllText(args[1],"LIFECYCLE_TEST_PASS");return 0;
  }catch(Exception e){File.WriteAllText(args[1],e.ToString());return 1;}
  finally {Stop(orphan);Stop(owner);Stop(first);Stop(second);Stop(unrelated);}
 }
}
