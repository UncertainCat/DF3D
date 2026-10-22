using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Win32;

// Windows preview bootstrap. Each play session owns its DF and viewer processes.
namespace DF3D.Release {
 public class PayloadFile { public string path; public string sha256; public long size; }
 public class GameVersion { public string version; public string steamBuildId; public uint peTimestamp; }
 public class Manifest { public int formatVersion; public string version; public GameVersion dwarfFortress; public string viewerExecutable; public string bridgeRoot; public List<PayloadFile> files; }
 public class InstalledVersion { public int formatVersion; public string version; }
 public class Change { public string relative; public string backup; public string beforeHash; public string installedHash; }
 public class Transaction { public string destination; public List<Change> changes = new List<Change>(); public bool complete; }
 public static class Package {
  public static readonly string Home = Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DF3D");
  public static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = 64000000 };
  public static string Hash(Stream stream) { using(var h=SHA256.Create()) return BitConverter.ToString(h.ComputeHash(stream)).Replace("-", "").ToLowerInvariant(); }
  public static string HashFile(string path) { using(var f=File.OpenRead(path)) return Hash(f); }
  public static string Inside(string root,string relative) {
   if(string.IsNullOrWhiteSpace(relative)||Path.IsPathRooted(relative)||relative.IndexOf(':')>=0) throw new IOException("Invalid package path");
   root=Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar)+Path.DirectorySeparatorChar;
   string path=Path.GetFullPath(Path.Combine(root,relative.Replace('/',Path.DirectorySeparatorChar)));
   if(!path.StartsWith(root,StringComparison.OrdinalIgnoreCase)) throw new IOException("Path escapes destination");
   for(string p=Path.GetDirectoryName(path);p!=null && p.Length>=root.Length-1;p=Path.GetDirectoryName(p))
    if(Directory.Exists(p)&&(File.GetAttributes(p)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked installation folders are not supported: "+p);
   if(File.Exists(path)&&(File.GetAttributes(path)&FileAttributes.ReparsePoint)!=0) throw new IOException("Linked target file: "+path);
   return path;
  }
  public static void AtomicJson(string path,object value) {
   Directory.CreateDirectory(Path.GetDirectoryName(path)); string tmp=path+".tmp";
   File.WriteAllText(tmp,Json.Serialize(value));
   if(File.Exists(path)) File.Replace(tmp,path,null); else File.Move(tmp,path);
  }
  public static Manifest ReadManifest(string root) {
   var m=Json.Deserialize<Manifest>(File.ReadAllText(Inside(root,"manifest.json")));
   if(m.formatVersion!=1||m.files==null||m.dwarfFortress==null) throw new IOException("Unsupported package manifest");
   var seen=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   foreach(var f in m.files) {
    string p=Inside(root,f.path);
    if(!seen.Add(p)||!File.Exists(p)||new FileInfo(p).Length!=f.size||!string.Equals(HashFile(p),f.sha256,StringComparison.OrdinalIgnoreCase)) throw new IOException("Package verification failed: "+f.path);
   }
   if(!seen.Contains(Inside(root,m.viewerExecutable))) throw new IOException("Viewer is absent from manifest");
   return m;
  }
  public static string Extract(string destination=null) {
   using(var source=Assembly.GetExecutingAssembly().GetManifestResourceStream("DF3D.Payload.zip")) {
    if(source==null) throw new IOException("Embedded payload missing");
    string id=Hash(source); source.Position=0;
    string target=destination ?? Path.Combine(Home,"versions",id);
    if(Directory.Exists(target) && File.Exists(Path.Combine(target,"manifest.json"))) { using(var zip=new ZipArchive(source,ZipArchiveMode.Read,true)) using(var entry=zip.GetEntry("manifest.json").Open()) { if(Hash(entry)!=HashFile(Path.Combine(target,"manifest.json")))throw new IOException("Cached manifest changed. Remove the affected version folder and relaunch."); } ReadManifest(target); return target; }
    string staging=target+".extract-"+Guid.NewGuid().ToString("N"); Directory.CreateDirectory(staging);
    using(var zip=new ZipArchive(source,ZipArchiveMode.Read)) foreach(var entry in zip.Entries) {
     string p=Inside(staging,entry.FullName);
     if(entry.FullName.EndsWith("/")) { Directory.CreateDirectory(p); continue; }
     Directory.CreateDirectory(Path.GetDirectoryName(p)); entry.ExtractToFile(p,false);
    }
    ReadManifest(staging); Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(target)));
    Directory.Move(staging,target); return target;
   }
  }
  public static uint PeTimestamp(string path) {
   using(var f=new BinaryReader(File.OpenRead(path))) {
    if(f.ReadUInt16()!=0x5a4d) throw new IOException("Not a Windows executable");
    f.BaseStream.Position=0x3c; int offset=f.ReadInt32();
    if(offset<0||offset>f.BaseStream.Length-12) throw new IOException("Invalid executable header");
    f.BaseStream.Position=offset; if(f.ReadUInt32()!=0x4550) throw new IOException("Invalid PE header");
    f.ReadUInt16();f.ReadUInt16();return f.ReadUInt32();
   }
  }
  public static void ValidateGame(string path,Manifest m) { InspectGame(path,m); }
  public static string InspectGame(string path,Manifest m) {
   if(!File.Exists(Inside(path,"Dwarf Fortress.exe")))throw new IOException("Choose Dwarf Fortress.exe.");
   if(PeTimestamp(Inside(path,"Dwarf Fortress.exe"))!=m.dwarfFortress.peTimestamp)
    throw new IOException("Unsupported DF version. Requires DF "+m.dwarfFortress.version+" (Steam build "+m.dwarfFortress.steamBuildId+").");
   if(!Directory.Exists(Path.Combine(path,"data","vanilla"))) throw new IOException("Dwarf Fortress data/vanilla folder is missing");
   return ValidateDfhack(path,m);
  }
  static IEnumerable<string> IntegrationFiles(string destination) {
   // Do not follow directory links while looking for an existing runtime.
   string hack=Inside(destination,"hack");
   if(Directory.Exists(hack)) {
    var pending=new Stack<string>();pending.Push(hack);
    while(pending.Count!=0) {
     string directory=pending.Pop();
     if((File.GetAttributes(directory)&FileAttributes.ReparsePoint)!=0)throw new IOException("Linked DFHack folders are not supported.");
     foreach(string file in Directory.GetFiles(directory))yield return file;
     foreach(string child in Directory.GetDirectories(directory))pending.Push(child);
    }
   }
   foreach(string file in Directory.GetFiles(destination)) {
    string name=Path.GetFileName(file);
    if(name.StartsWith("dfhack",StringComparison.OrdinalIgnoreCase)||name.StartsWith("dfhooks",StringComparison.OrdinalIgnoreCase))yield return file;
   }
  }
  public const string VersionFile="df3d-install.json";
  public static string ValidateDfhack(string destination,Manifest m) {
   destination=Path.GetFullPath(destination);
   string marker=Inside(destination,VersionFile);
   if(File.Exists(marker)) {
    try {
     var installed=Json.Deserialize<InstalledVersion>(File.ReadAllText(marker));
     if(installed!=null&&installed.formatVersion==1&&!string.IsNullOrWhiteSpace(installed.version))
      return installed.version==m.version?"current":"update";
    } catch(ArgumentException){}catch(InvalidOperationException){}
    throw new IOException("Invalid DF3D version record. Restore bridge files, then try again.");
   }
   if(!IntegrationFiles(destination).Any())return "clean";
   throw new IOException("Unsupported DFHack installation. Uninstall DFHack, then try again.");
  }
  public static void RequireClosed() {
   if(Process.GetProcessesByName("Dwarf Fortress").Length!=0) throw new IOException("Close Dwarf Fortress before installing or restoring the bridge.");
  }
  public static string Install(string root,Manifest m,string destination) {
   RequireClosed();
   InspectGame(destination,m);
   if(string.IsNullOrWhiteSpace(m.version))throw new IOException("Package version is missing.");
   byte[] markerBytes=System.Text.Encoding.UTF8.GetBytes(Json.Serialize(new InstalledVersion{formatVersion=1,version=m.version}));
   string backups=Path.Combine(Home,"backups");
   if(Directory.Exists(backups)) foreach(string prior in Directory.GetFiles(backups,"transaction.json",SearchOption.AllDirectories)) {
    var previous=Json.Deserialize<Transaction>(File.ReadAllText(prior));
    if(!previous.complete && string.Equals(Path.GetFullPath(destination),previous.destination,StringComparison.OrdinalIgnoreCase))
     throw new IOException("An interrupted setup must be restored before retrying. Use Restore bridge files and select: "+prior);
   }
   var transaction=new Transaction { destination=Path.GetFullPath(destination) };
   string folder=Path.Combine(Home,"backups",DateTime.UtcNow.ToString("yyyyMMdd-HHmmss")+"-"+Guid.NewGuid().ToString("N"));
   string journal=Path.Combine(folder,"transaction.json");
   foreach(var f in m.files.Where(x=>x.path.StartsWith(m.bridgeRoot.TrimEnd('/')+"/",StringComparison.Ordinal))) {
    string relative=f.path.Substring(m.bridgeRoot.TrimEnd('/').Length+1);
    string target=Inside(destination,relative);
    if(File.Exists(target)&&HashFile(target).Equals(f.sha256,StringComparison.OrdinalIgnoreCase)) continue;
    var c=new Change { relative=relative, installedHash=f.sha256 };
    if(File.Exists(target)) { c.beforeHash=HashFile(target); c.backup=Inside(folder,"original/"+relative); Directory.CreateDirectory(Path.GetDirectoryName(c.backup)); File.Copy(target,c.backup); }
    transaction.changes.Add(c);
   }
   string markerTarget=Inside(destination,VersionFile);
   string markerHash;using(var stream=new MemoryStream(markerBytes))markerHash=Hash(stream);
   if(!File.Exists(markerTarget)||HashFile(markerTarget)!=markerHash) {
    var change=new Change{relative=VersionFile,installedHash=markerHash};
    if(File.Exists(markerTarget)){change.beforeHash=HashFile(markerTarget);change.backup=Inside(folder,"original/"+VersionFile);Directory.CreateDirectory(Path.GetDirectoryName(change.backup));File.Copy(markerTarget,change.backup);}
    transaction.changes.Add(change); // Publish the version only after all payload files succeed.
   }
   if(transaction.changes.Count==0) return null;
   AtomicJson(journal,transaction); // Recovery intent is durable before the first install write.
   try {
    foreach(var c in transaction.changes) {
     string target=Inside(destination,c.relative); Directory.CreateDirectory(Path.GetDirectoryName(target));
     string temp=target+".df3d-"+Guid.NewGuid().ToString("N");
     if(c.relative==VersionFile)File.WriteAllBytes(temp,markerBytes);
     else File.Copy(Inside(root,m.bridgeRoot+"/"+c.relative),temp);
     if(File.Exists(target)) File.Replace(temp,target,null); else File.Move(temp,target);
    }
    transaction.complete=true; AtomicJson(journal,transaction); return journal;
   } catch { Restore(journal); throw; }
  }
  public static void Restore(string journal) {
   RequireClosed(); var t=Json.Deserialize<Transaction>(File.ReadAllText(journal));
   // Validate the whole restoration before writing anything. Never overwrite later user changes.
   foreach(var c in t.changes) {
    string target=Inside(t.destination,c.relative);
    if(File.Exists(target)) { string h=HashFile(target); if(!h.Equals(c.installedHash,StringComparison.OrdinalIgnoreCase)&&h!=c.beforeHash) throw new IOException("File changed since setup; automatic restore stopped: "+target); }
    if(c.backup!=null && (!File.Exists(c.backup)||HashFile(c.backup)!=c.beforeHash)) throw new IOException("Backup verification failed: "+c.relative);
   }
   foreach(var c in t.changes.AsEnumerable().Reverse()) {
    string target=Inside(t.destination,c.relative);
    if(c.backup==null) { if(File.Exists(target))File.Delete(target); }
    else {
     Directory.CreateDirectory(Path.GetDirectoryName(target));string temp=target+".df3d-restore-"+Guid.NewGuid().ToString("N");
     File.Copy(c.backup,temp);if(File.Exists(target))File.Replace(temp,target,null);else File.Move(temp,target);
    }
   }
   File.Move(journal,journal+".restored");
  }
  public static IEnumerable<string> Discover() {
   string supplied=Environment.GetEnvironmentVariable("DF3D_DF_PATH");
   if(!string.IsNullOrWhiteSpace(supplied))return new[]{Path.GetFullPath(supplied)};
   var roots=new HashSet<string>(StringComparer.OrdinalIgnoreCase);
   string steamRoot=Environment.GetEnvironmentVariable("DF3D_STEAM_ROOT");
   if(!string.IsNullOrWhiteSpace(steamRoot))roots.Add(steamRoot);
   else {
    using(var key=Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam")) { if(key!=null&&key.GetValue("SteamPath")!=null)roots.Add(key.GetValue("SteamPath").ToString()); }
    foreach(string registryPath in new[]{@"Software\Valve\Steam",@"Software\WOW6432Node\Valve\Steam"})using(var key=Registry.LocalMachine.OpenSubKey(registryPath)){if(key!=null&&key.GetValue("InstallPath")!=null)roots.Add(key.GetValue("InstallPath").ToString());}
    roots.Add(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),"Steam"));
   }
   foreach(var root in roots.ToArray()) {
    string vdf=Path.Combine(root,"steamapps","libraryfolders.vdf");
    if(File.Exists(vdf)) foreach(Match match in Regex.Matches(File.ReadAllText(vdf),"\"(?:path|[0-9]+)\"\\s+\"([^\"]+)\"")) {string candidate=match.Groups[1].Value.Replace(@"\\",@"\");if(Path.IsPathRooted(candidate))roots.Add(candidate);}
   }
   var found=new List<string>();
   foreach(string library in roots){
    string manifest=Path.Combine(library,"steamapps","appmanifest_975370.acf");if(!File.Exists(manifest))continue;
    string text=File.ReadAllText(manifest);
    if(!Regex.IsMatch(text,"\"appid\"\\s+\"975370\""))continue;
    var match=Regex.Match(text,"\"installdir\"\\s+\"([^\"]+)\"");if(!match.Success)continue;
    string directory=Path.GetFullPath(Path.Combine(library,"steamapps","common",match.Groups[1].Value.Replace(@"\\",@"\")));
    if(File.Exists(Path.Combine(directory,"Dwarf Fortress.exe")))found.Add(directory);
   }
   return found.Distinct(StringComparer.OrdinalIgnoreCase);
  }
 }
 public sealed class OwnedSession : IDisposable {
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CreateDesktop(string name,IntPtr device,IntPtr mode,uint flags,uint access,IntPtr security);
    [DllImport("user32.dll", SetLastError=true)]
    static extern bool CloseDesktop(IntPtr desktop);
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
    static extern IntPtr CreateJobObject(IntPtr attrs, string name);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint len);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool TerminateProcess(IntPtr process, uint code);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr h);

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
        public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit;
        public UIntPtr Affinity; public uint PriorityClass, SchedulingClass;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS { public ulong a, b, c, d, e, f; }
    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION Basic; public IO_COUNTERS Io;
        public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
    }


    IntPtr job, desktop;
    string desktopName;
    static OwnedSession launcherLifetime;
    // Intentionally held until process exit, not disposed: this job includes
    // the launcher itself. Windows closes its handle even after a hard kill,
    // taking every descendant with it (including helpers outside a play job).
    public static void ContainLauncher() {
        if(launcherLifetime!=null)return;
        var lifetime=new OwnedSession();
        using(var current=Process.GetCurrentProcess()) {
            if(!AssignProcessToJobObject(lifetime.job,current.Handle)) {
                int error=Marshal.GetLastWin32Error();lifetime.Dispose();
                throw new Win32Exception(error,"Cannot contain launcher process tree");
            }
        }
        launcherLifetime=lifetime;
    }
    public OwnedSession() {
        job=CreateJobObject(IntPtr.Zero,null);
        if(job==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());
        var limits=new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();limits.Basic.LimitFlags=0x2000;
        int size=Marshal.SizeOf(limits);IntPtr buffer=Marshal.AllocHGlobal(size);
        try {Marshal.StructureToPtr(limits,buffer,false);if(!SetInformationJobObject(job,9,buffer,(uint)size))throw new Win32Exception(Marshal.GetLastWin32Error());}
        catch {Dispose();throw;}
        finally {Marshal.FreeHGlobal(buffer);}
    }
    public Process Start(ProcessStartInfo start, bool hiddenDesktop=false) {
        if(job==IntPtr.Zero)throw new ObjectDisposedException("OwnedSession");
        if(hiddenDesktop && desktop==IntPtr.Zero) {
            desktopName="df3d_"+Guid.NewGuid().ToString("N");
            desktop=CreateDesktop(desktopName,IntPtr.Zero,IntPtr.Zero,0,0x10000000,IntPtr.Zero);
            if(desktop==IntPtr.Zero)throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        string env=string.Join("\0",start.EnvironmentVariables.Keys.Cast<string>().OrderBy(k=>k,StringComparer.OrdinalIgnoreCase).Select(k=>k+"="+start.EnvironmentVariables[k]))+"\0\0";
        IntPtr environment=Marshal.StringToHGlobalUni(env);
        var si=new STARTUPINFO();si.cb=Marshal.SizeOf(si);
        si.lpDesktop=hiddenDesktop?desktopName:null;
        PROCESS_INFORMATION pi;
        try {if(!CreateProcess(start.FileName,"\""+start.FileName+"\" "+start.Arguments,IntPtr.Zero,IntPtr.Zero,false,0x404,environment,start.WorkingDirectory,ref si,out pi))throw new Win32Exception(Marshal.GetLastWin32Error());}
        finally {Marshal.FreeHGlobal(environment);}
        try {
            if(!AssignProcessToJobObject(job,pi.hProcess))throw new Win32Exception(Marshal.GetLastWin32Error());
            var process=Process.GetProcessById(pi.dwProcessId);
            // Hold a handle to this exact process, independent of future PID reuse.
            var handle=process.Handle;
            if(ResumeThread(pi.hThread)==uint.MaxValue){process.Dispose();throw new Win32Exception(Marshal.GetLastWin32Error());}
            return process;
        } catch {TerminateProcess(pi.hProcess,1);throw;}
        finally {CloseHandle(pi.hThread);CloseHandle(pi.hProcess);}
    }
    public void Dispose(){if(job!=IntPtr.Zero){CloseHandle(job);job=IntPtr.Zero;}if(desktop!=IntPtr.Zero){CloseDesktop(desktop);desktop=IntPtr.Zero;}}
 }
 public sealed class Launcher : Form {
  TextBox path=new TextBox(); CheckBox acknowledge=new CheckBox();
  int commandPort=5000; string root; Manifest manifest; Process game,audioGuard; bool playing; OwnedSession playSession; string lastJournal; bool busy;
  string settings=Path.Combine(Package.Home,"launcher.json");
  Process appProcess; OwnedSession appSession; Timer poll; string channel;
  Dictionary<string,Dictionary<string,object>> inspections=new Dictionary<string,Dictionary<string,object>>(StringComparer.OrdinalIgnoreCase);
  Dictionary<string,string> saved=new Dictionary<string,string>();
  protected override void SetVisibleCore(bool value){base.SetVisibleCore(false);}
  public Launcher(string payload, string setupScript="res://scripts/setup_launcher.gd") {
   OwnedSession.ContainLauncher();
   root=payload;manifest=Package.ReadManifest(root);
   try {if(File.Exists(settings))saved=Package.Json.Deserialize<Dictionary<string,string>>(File.ReadAllText(settings));}catch{}
   if(saved==null)saved=new Dictionary<string,string>();
   if(saved.ContainsKey("journal"))lastJournal=saved["journal"];
   channel=Path.Combine(Package.Home,"setup",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(channel);
   foreach(string candidate in Package.Discover().Concat(saved.ContainsKey("installation")?new[]{saved["installation"]}:new string[0]).Where(x=>!string.IsNullOrWhiteSpace(x)).Distinct(StringComparer.OrdinalIgnoreCase)) InspectTarget(candidate);
   appSession=new OwnedSession();
   var info=StartInfo(Package.Inside(root,manifest.viewerExecutable),"--log-file \""+Path.Combine(channel,"ui.log")+"\"",Path.GetDirectoryName(Package.Inside(root,manifest.viewerExecutable)));
   foreach(string key in info.EnvironmentVariables.Keys.Cast<string>().Where(x=>x.StartsWith("DF3D_") && x!="DF3D_CACHE_DIR" && !(setupScript!="res://scripts/setup_launcher.gd" && x.StartsWith("DF3D_SETUP_"))).ToArray())info.EnvironmentVariables.Remove(key);
   info.EnvironmentVariables["DF3D_PROFILE"]="off";info.EnvironmentVariables["DF3D_RELEASE"]="1";
   info.EnvironmentVariables["DF3D_SETUP_CHANNEL"]=channel;
   info.EnvironmentVariables["DF3D_SETUP_SCRIPT"]=setupScript;
   info.EnvironmentVariables["DF3D_SETUP_ICON"]=Path.Combine(root,"helpers","godot-icon.png");
   appProcess=appSession.Start(info);
   poll=new Timer {Interval=100};poll.Tick+=async(s,e)=>await PollSetup();poll.Start();
   FormClosed+=(s,e)=>{poll.Stop();CleanupPlay();appSession.Dispose();appProcess.Dispose();};
  }
  Dictionary<string,object> InspectTarget(string target) {
   var result=new Dictionary<string,object>();
   try {target=Path.GetFullPath(target);result["state"]=Package.InspectGame(target,manifest);result["ok"]=true;}
   catch(IOException ex){result["ok"]=false;result["error"]=ex.Message;}
   catch(UnauthorizedAccessException ex){result["ok"]=false;result["error"]=ex.Message;}
   catch(ArgumentException){result["ok"]=false;result["error"]="Choose Dwarf Fortress.exe.";}
   inspections[target]=result;return result;
  }
  async Task PollSetup() {
   if(appProcess.HasExited){if(!busy||game!=null){CleanupPlay();Environment.Exit(0);}return;}
   if(playing && game.HasExited){CleanupPlay();Environment.Exit(0);}
   if(playing && !File.Exists(Path.Combine(channel,"request.json")))return;
   string request=Path.Combine(channel,"request.json");
   if(busy||!File.Exists(request))return;
   busy=true;
   var response=new Dictionary<string,object>();
   try {
    var r=Package.Json.Deserialize<Dictionary<string,string>>(File.ReadAllText(request));File.Delete(request);
    string action=r["action"];
    response["ok"]=true;
    if(action=="bootstrap") {
     response["suggestions"]=inspections.Keys.ToArray();
     response["inspections"]=inspections;
     response["installation"]=saved.ContainsKey("installation")?saved["installation"]:"";
     response["accepted"]=saved.ContainsKey("acknowledgment")&&saved["acknowledgment"]=="1";
    } else if(action=="target") {
     path.Text="";acknowledge.Checked=false;
     string target=Path.GetFullPath(r["path"]);
     var inspection=inspections.ContainsKey(target)?inspections[target]:InspectTarget(target);
     if(!(bool)inspection["ok"])throw new IOException((string)inspection["error"]);
     path.Text=target;acknowledge.Checked=saved.ContainsKey("installation")&&string.Equals(saved["installation"],target,StringComparison.OrdinalIgnoreCase)&&saved.ContainsKey("acknowledgment")&&saved["acknowledgment"]=="1";
     response["state"]=inspection["state"];
     response["accepted"]=acknowledge.Checked;
     var saves=new List<string>{Path.Combine(target,"save")};
     string user=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Bay 12 Games","Dwarf Fortress","save");
     if(Directory.Exists(user))saves.Add(user);
     response["saves"]=saves;
    } else if(action=="accept") {
     Package.ValidateGame(path.Text,manifest);acknowledge.Checked=true;SaveSettings();
    } else if(action=="install") {
     Check();string target=path.Text;
     string journal=await Task.Run(()=>Package.Install(root,manifest,target));
     if(journal!=null)lastJournal=journal;SaveSettings();InspectTarget(target);
    } else if(action=="play") {await StartGame();}
    else if(action=="abort-play") {CleanupPlay();}
    else if(action=="restore") {
     using(var picker=new OpenFileDialog {Title="Select installation backup",InitialDirectory=Path.Combine(Package.Home,"backups"),Filter="DF3D transaction|transaction.json"}) {
      if(picker.ShowDialog()==DialogResult.OK){string journal=picker.FileName;await Task.Run(()=>Package.Restore(journal));inspections.Clear();}
     }
    } else throw new IOException("Unknown setup action");
   } catch(Exception ex){response["ok"]=false;response["error"]=ex.Message;Say(ex.Message);}
   finally {Package.AtomicJson(Path.Combine(channel,"response.json"),response);busy=false;}
  }
  void Check(){if(!acknowledge.Checked)throw new IOException("Confirm that you understand DF3D is unstable first.");}
  void SaveSettings(){saved=new Dictionary<string,string>{{"installation",Path.GetFullPath(path.Text)},{"journal",lastJournal},{"acknowledgment",acknowledge.Checked?"1":"0"}};Package.AtomicJson(settings,saved);}
  void Say(string text){Directory.CreateDirectory(Package.Home);File.AppendAllText(Path.Combine(Package.Home,"launcher.log"),DateTime.UtcNow.ToString("o")+" "+text+Environment.NewLine);}
  static ProcessStartInfo StartInfo(string exe,string args,string cwd){return new ProcessStartInfo(exe,args){WorkingDirectory=cwd,UseShellExecute=false};}
  async Task<string> Command(string installation,string command){var p=StartInfo(Path.Combine(installation,"hack","dfhack-run.exe"),command,installation);p.CreateNoWindow=true;p.RedirectStandardOutput=true;p.RedirectStandardError=true;p.EnvironmentVariables["DFHACK_PORT"]=commandPort.ToString();using(var proc=Process.Start(p)){var output=proc.StandardOutput.ReadToEndAsync();var error=proc.StandardError.ReadToEndAsync();if(!await Task.Run(()=>proc.WaitForExit(4000))){proc.Kill();throw new IOException("DFHack command timed out");}string result=await output+await error;if(proc.ExitCode!=0)throw new IOException(result.Trim());return result;}}
  async Task GuardAudio(){
   string folder=Path.Combine(Package.Home,"audio",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);string statusFile=Path.Combine(folder,"status");
   string args="--guard "+appProcess.Id+" "+appProcess.StartTime.ToFileTimeUtc()+" "+game.Id+" "+game.StartTime.ToFileTimeUtc()+" \""+statusFile+"\" \""+Path.Combine(folder,"stop")+"\"";
   var info=StartInfo(Package.Inside(root,"helpers/audio_guard.exe"),args,folder);info.CreateNoWindow=true;audioGuard=Process.Start(info);var guard=audioGuard;
   var until=DateTime.UtcNow.AddSeconds(15);while(!File.Exists(statusFile)&&!guard.HasExited&&DateTime.UtcNow<until)await Task.Delay(100);
   if(!File.Exists(statusFile)||File.ReadAllText(statusFile).Trim()!="READY")Say("Native audio takeover was not confirmed. Check Windows Volume Mixer. "+folder);
  }
  void CleanupPlay(){
   playing=false;
   if(playSession!=null){playSession.Dispose();playSession=null;}
   if(game!=null){game.WaitForExit(5000);game.Dispose();game=null;}
   if(audioGuard!=null){try{if(!audioGuard.WaitForExit(5000)){try{audioGuard.Kill();}catch(InvalidOperationException){}audioGuard.WaitForExit(5000);}}finally{audioGuard.Dispose();audioGuard=null;}}
  }
  async Task StartGame(){
   Check();string installation=Path.GetFullPath(path.Text);
   if(Package.InspectGame(installation,manifest)!="current")throw new IOException("Set up DF3D before launching.");
   if(playSession!=null)throw new IOException("DF3D is already running.");
   Package.RequireClosed();
   commandPort=5000;
   playSession=new OwnedSession();
   try {
    var si=StartInfo(Path.Combine(installation,"Dwarf Fortress.exe"),"",installation);
    si.EnvironmentVariables["DFHACK_DISABLE_CONSOLE"]="1";si.EnvironmentVariables["DFHACK_PORT"]="5000";
    game=playSession.Start(si,true);
    Say("Waiting for Dwarf Fortress.");
    string lastError="";bool ready=false;var deadline=DateTime.UtcNow.AddSeconds(120);
    while(DateTime.UtcNow<deadline){
     if(game.HasExited)throw new IOException("Dwarf Fortress exited before the bridge was ready.");
     try{await Command(installation,"enable df3d");string result=await Command(installation,"df3d status");if(Regex.IsMatch(result,@"mirroring enabled:\s+yes")){ready=true;break;}}
     catch(IOException ex){lastError=ex.Message;}
     await Task.Delay(500);
    }
    if(!ready)throw new IOException("Bridge did not become ready. The session will be cleaned up. "+lastError);
    SaveSettings();await GuardAudio();
    if(game.HasExited)throw new IOException("Dwarf Fortress exited during startup.");
    playing=true;
    Say("Dwarf Fortress ready. The DF3D window will enter the game.");
   } catch {CleanupPlay();throw;}
  }

 }
 public static class Program {
  [STAThread] public static int Main(string[] args){try{Directory.CreateDirectory(Package.Home);if(args.Length>0&&args[0]=="--extract-only"){if(args.Length!=2)return 2;Package.Extract(args[1]);return 0;}if(args.Length>0&&args[0]=="--self-test"){SelfTest();return 0;}Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);bool created;using(var mutex=new System.Threading.Mutex(true,@"Local\DF3D.ReleaseLauncher",out created)){if(!created){MessageBox.Show("DF3D launcher is already open.");return 1;}Application.Run(new Launcher(Package.Extract()));}return 0;}catch(Exception ex){File.AppendAllText(Path.Combine(Package.Home,"launcher.log"),ex.ToString()+Environment.NewLine);if(args.Length==0)MessageBox.Show(ex.Message,"DF3D setup");return 1;}}
  static void InstallationTests(string temp) {
   string source=Path.Combine(temp,"source"), dest=Path.Combine(temp,"game");Directory.CreateDirectory(Path.Combine(source,"bridge"));Directory.CreateDirectory(Path.Combine(dest,"data","vanilla"));
   using(var pe=new BinaryWriter(File.Create(Path.Combine(dest,"Dwarf Fortress.exe")))){pe.Write((ushort)0x5a4d);pe.BaseStream.Position=0x3c;pe.Write(128);pe.BaseStream.Position=128;pe.Write((uint)0x4550);pe.Write((ushort)0);pe.Write((ushort)0);pe.Write((uint)1234);}
   File.WriteAllText(Path.Combine(source,"bridge","test.dll"),"new");File.WriteAllText(Path.Combine(dest,"test.dll"),"original");
   File.WriteAllText(Path.Combine(source,"bridge","added.dll"),"added");
   var manifest=new Manifest {version="test.1",bridgeRoot="bridge",dwarfFortress=new GameVersion {peTimestamp=1234},files=new List<PayloadFile>()};
   foreach(string name in new[]{"test.dll","added.dll"})manifest.files.Add(new PayloadFile {path="bridge/"+name,sha256=Package.HashFile(Path.Combine(source,"bridge",name))});
   string journal=Package.Install(source,manifest,dest);
   if(File.ReadAllText(Path.Combine(dest,"test.dll"))!="new")throw new Exception("Install failed");
   if(Package.Install(source,manifest,dest)!=null)throw new Exception("Identical install wrote files");
   var interrupted=Package.Json.Deserialize<Transaction>(File.ReadAllText(journal));interrupted.complete=false;Package.AtomicJson(journal,interrupted);
   bool refused=false;try{Package.Install(source,manifest,dest);}catch(IOException){refused=true;}if(!refused)throw new Exception("Interrupted transaction ignored");
   File.WriteAllText(Path.Combine(dest,"test.dll"),"user edit");refused=false;try{Package.Restore(journal);}catch(IOException){refused=true;}if(!refused)throw new Exception("Restore overwrote user edit");
   File.WriteAllText(Path.Combine(dest,"test.dll"),"new");Package.Restore(journal);
   if(File.ReadAllText(Path.Combine(dest,"test.dll"))!="original"||File.Exists(Path.Combine(dest,"added.dll")))throw new Exception("Restore failed");
   manifest.dwarfFortress.peTimestamp=999;refused=false;try{Package.ValidateGame(dest,manifest);}catch(IOException){refused=true;}if(!refused)throw new Exception("Wrong version accepted");
  }
  static void DiscoveryTests(string temp) {
   string oldRoot=Environment.GetEnvironmentVariable("DF3D_STEAM_ROOT"),oldDf=Environment.GetEnvironmentVariable("DF3D_DF_PATH");
   try {
    string steam=Path.Combine(temp,"Steam root"),library=Path.Combine(temp,"Secondary library"),game=Path.Combine(library,"steamapps","common","Custom DF folder");
    Directory.CreateDirectory(Path.Combine(steam,"steamapps"));Directory.CreateDirectory(game);
    File.WriteAllText(Path.Combine(game,"Dwarf Fortress.exe"),"stand-in");
    File.WriteAllText(Path.Combine(steam,"steamapps","libraryfolders.vdf"),"\"libraryfolders\" { \"1\" { \"path\" \""+library.Replace(@"\",@"\\")+"\" } }");
    string manifest=Path.Combine(library,"steamapps","appmanifest_975370.acf");
    File.WriteAllText(manifest,"\"AppState\" { \"appid\" \"975370\" \"installdir\" \"Custom DF folder\" }");
    Environment.SetEnvironmentVariable("DF3D_STEAM_ROOT",steam);Environment.SetEnvironmentVariable("DF3D_DF_PATH",null);
    if(Package.Discover().Single()!=game)throw new Exception("Secondary library discovery failed");
    File.WriteAllText(manifest,"\"AppState\" { \"appid\" \"wrong\" \"installdir\" \"Custom DF folder\" }");
    if(Package.Discover().Any())throw new Exception("Wrong Steam app accepted");
    string missing=Path.Combine(temp,"Explicit missing installation");Environment.SetEnvironmentVariable("DF3D_DF_PATH",missing);
    if(Package.Discover().Single()!=missing)throw new Exception("Explicit override was silently replaced");
   } finally {Environment.SetEnvironmentVariable("DF3D_STEAM_ROOT",oldRoot);Environment.SetEnvironmentVariable("DF3D_DF_PATH",oldDf);}
  }
  static void SelfTest(){string temp=Path.Combine(Path.GetTempPath(),"df3d-launcher-test-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(temp);foreach(string bad in new[]{"../escape","C:/escape","/escape","a/../../escape","file:stream"}){bool rejected=false;try{Package.Inside(temp,bad);}catch(IOException){rejected=true;}if(!rejected)throw new Exception("Unsafe path accepted");}Package.AtomicJson(Path.Combine(temp,"test.json"),new Dictionary<string,int>{{"value",1}});Package.AtomicJson(Path.Combine(temp,"test.json"),new Dictionary<string,int>{{"value",2}});if(!File.ReadAllText(Path.Combine(temp,"test.json")).Contains("2"))throw new Exception("Atomic update failed");DiscoveryTests(temp);InstallationTests(temp);string extracted=Package.Extract(Path.Combine(temp,"payload"));Package.ReadManifest(extracted);File.WriteAllText(Path.Combine(Package.Home,"self-test.txt"),"PASS "+extracted);}
 }
}
