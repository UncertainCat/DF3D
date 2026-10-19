using System;
using System.Diagnostics;
using System.IO;
using System.Threading;
using DF3D.Release;

// Stand-ins only: never launches or searches for the real game.
public static class LifecycleTests {
 static string Self { get { return typeof(LifecycleTests).Assembly.Location; } }
 static ProcessStartInfo Info(string args) { return new ProcessStartInfo(Self,args) {UseShellExecute=false,CreateNoWindow=true,WorkingDirectory=Path.GetDirectoryName(Self)}; }
 static void Require(bool value,string message) {if(!value)throw new Exception(message);}
 static void Stop(Process p) {if(p==null)return;try{if(!p.HasExited)p.Kill();p.WaitForExit(5000);}finally{p.Dispose();}}
 [STAThread] public static int Main(string[] args) {
  if(args[0]=="--worker") {Thread.Sleep(60000);return 0;}
  if(args[0]=="--owner") {
   using(var session=new OwnedSession())using(var child=session.Start(Info("--worker"))) {
    File.WriteAllText(args[1],child.Id.ToString());Thread.Sleep(60000);
   }
   return 0;
  }
  Process unrelated=null,first=null,second=null,owner=null,orphan=null;
  try {
   unrelated=Process.Start(Info("--worker"));
   using(var session=new OwnedSession()) {
    first=session.Start(Info("--worker"));second=session.Start(Info("--worker"));
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
