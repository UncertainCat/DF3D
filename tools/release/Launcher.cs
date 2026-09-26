using System;
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

// Windows preview bootstrap. Never owns or terminates the DF process.
namespace DF3D.Release {
 public class PayloadFile { public string path; public string sha256; public long size; }
 public class GameVersion { public string version; public string steamBuildId; public uint peTimestamp; }
 public class Manifest { public int formatVersion; public string version; public GameVersion dwarfFortress; public string viewerExecutable; public string bridgeRoot; public List<PayloadFile> files; }
 public class Change { public string relative; public string backup; public string beforeHash; public string installedHash; }
 public class Transaction { public string destination; public List<Change> changes = new List<Change>(); public bool complete; }
 public static class Package {
  public static readonly string Home = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DF3D");
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
  public static void ValidateGame(string path,Manifest m) {
   if(PeTimestamp(Inside(path,"Dwarf Fortress.exe"))!=m.dwarfFortress.peTimestamp)
    throw new IOException("This preview requires Dwarf Fortress "+m.dwarfFortress.version+", Steam build "+m.dwarfFortress.steamBuildId+". The selected executable does not match.");
   if(!Directory.Exists(Path.Combine(path,"data","vanilla"))) throw new IOException("Dwarf Fortress data/vanilla folder is missing");
  }
  public static void RequireClosed() {
   if(Process.GetProcessesByName("Dwarf Fortress").Length!=0) throw new IOException("Close Dwarf Fortress before installing or restoring the bridge.");
  }
  public static string Install(string root,Manifest m,string destination) {
   RequireClosed(); ValidateGame(destination,m);
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
    string relative=f.path.Substring(m.bridgeRoot.TrimEnd('/').Length+1); string target=Inside(destination,relative);
    if(File.Exists(target)&&HashFile(target).Equals(f.sha256,StringComparison.OrdinalIgnoreCase)) continue;
    var c=new Change { relative=relative, installedHash=f.sha256 };
    if(File.Exists(target)) { c.beforeHash=HashFile(target); c.backup=Inside(folder,"original/"+relative); Directory.CreateDirectory(Path.GetDirectoryName(c.backup)); File.Copy(target,c.backup); }
    transaction.changes.Add(c);
   }
   if(transaction.changes.Count==0) return null;
   AtomicJson(journal,transaction); // Recovery intent is durable before the first install write.
   try {
    foreach(var c in transaction.changes) {
     string target=Inside(destination,c.relative); Directory.CreateDirectory(Path.GetDirectoryName(target));
     string temp=target+".df3d-"+Guid.NewGuid().ToString("N");
     File.Copy(Inside(root,m.bridgeRoot+"/"+c.relative),temp);
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
 public sealed class Launcher : Form {
  TextBox path=new TextBox(), status=new TextBox(); Button play=new Button(), setup=new Button(); CheckBox acknowledge=new CheckBox();
  int commandPort=5000; string root; Manifest manifest; Process game,viewer; string lastJournal; bool busy;
  string settings=Path.Combine(Package.Home,"launcher.json");
  public Launcher(string payload) {
   root=payload;manifest=Package.ReadManifest(root); Text="DF3D "+manifest.version+" Preview"; Width=720;Height=530;MinimumSize=new System.Drawing.Size(650,490);
   var box=new TableLayoutPanel { Dock=DockStyle.Fill,Padding=new Padding(20),ColumnCount=1,RowCount=7 }; Controls.Add(box);
   box.Controls.Add(new Label {Text="DF3D "+manifest.version+" Preview",Font=new System.Drawing.Font("Segoe UI",20),AutoSize=true});
   box.Controls.Add(new Label {Text="Select your Dwarf Fortress installation. Requires DF "+manifest.dwarfFortress.version+" (Steam build "+manifest.dwarfFortress.steamBuildId+").",AutoSize=true,MaximumSize=new System.Drawing.Size(650,0)});
   var row=new TableLayoutPanel {ColumnCount=2,Dock=DockStyle.Top,AutoSize=true};row.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100)); row.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize)); path.Dock=DockStyle.Fill;row.Controls.Add(path);var browse=new Button {Text="Browse…",AutoSize=true};row.Controls.Add(browse);box.Controls.Add(row);
   browse.Click+=(s,e)=>{using(var picker=new OpenFileDialog {Title="Select Dwarf Fortress.exe",Filter="Dwarf Fortress|Dwarf Fortress.exe"})if(picker.ShowDialog()==DialogResult.OK)path.Text=Path.GetDirectoryName(picker.FileName);};
   acknowledge.Text="I have backed up my saves and understand this preview is unstable.";acknowledge.AutoSize=true;box.Controls.Add(acknowledge);
   var buttons=new FlowLayoutPanel {AutoSize=true,Dock=DockStyle.Top};setup.Text="Set up bridge";setup.AutoSize=true;play.Text="Play";play.AutoSize=true;buttons.Controls.Add(setup);buttons.Controls.Add(play);
   var saves=new Button {Text="Save folders",AutoSize=true};buttons.Controls.Add(saves);var restore=new Button {Text="Restore bridge files",AutoSize=true};buttons.Controls.Add(restore);box.Controls.Add(buttons);
   status.Multiline=true;status.ReadOnly=true;status.ScrollBars=ScrollBars.Vertical;status.Dock=DockStyle.Fill;box.Controls.Add(status);box.RowStyles.Add(new RowStyle(SizeType.AutoSize));box.RowStyles.Add(new RowStyle(SizeType.AutoSize));box.RowStyles.Add(new RowStyle(SizeType.AutoSize));box.RowStyles.Add(new RowStyle(SizeType.AutoSize));box.RowStyles.Add(new RowStyle(SizeType.AutoSize));box.RowStyles.Add(new RowStyle(SizeType.Percent,100));
   var logs=new Button {Text="Open diagnostics",AutoSize=true};box.Controls.Add(logs); logs.Click+=(s,e)=>Process.Start("explorer.exe",Package.Home);
   try {if(File.Exists(settings)){var d=Package.Json.Deserialize<Dictionary<string,string>>(File.ReadAllText(settings));path.Text=d["installation"];lastJournal=d.ContainsKey("journal")?d["journal"]:null;}}catch{}
   if(!string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable("DF3D_DF_PATH"))||path.Text.Length==0||!File.Exists(Path.Combine(path.Text,"Dwarf Fortress.exe")))path.Text=Package.Discover().FirstOrDefault()??"";
   setup.Click+=async(s,e)=>await Run(async()=>{Check();Package.RequireClosed();Package.ValidateGame(path.Text,manifest);if(MessageBox.Show("Install the bundled DFHack build and DF3D bridge into:\n"+path.Text+"\n\nExisting replaced files will be backed up under:\n"+Package.Home+"\\backups\n\nSaves and DF settings are not replaced. Existing extra plugins and settings remain and may conflict. Close DF before restoring files.","Set up bridge",MessageBoxButtons.OKCancel)!=DialogResult.OK)return; string dest=path.Text;string j=await Task.Run(()=>Package.Install(root,manifest,dest));if(j!=null)lastJournal=j;SaveSettings();Say("Bridge ready. Original files are backed up. You can now Play.");});
   restore.Click+=async(s,e)=>await Run(async()=>{using(var picker=new OpenFileDialog {Title="Select installation backup",InitialDirectory=Path.Combine(Package.Home,"backups"),Filter="DF3D transaction|transaction.json"}){if(lastJournal!=null)picker.FileName=lastJournal;if(picker.ShowDialog()!=DialogResult.OK)return;string journal=picker.FileName;await Task.Run(()=>Package.Restore(journal));Say("Bridge files restored. Backups retained.");}});
   saves.Click+=(s,e)=>{string user=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"Bay 12 Games","Dwarf Fortress","save");if(Directory.Exists(user))Process.Start("explorer.exe",user);string local=Path.Combine(path.Text,"save");if(Directory.Exists(local))Process.Start("explorer.exe",local);Say("Copy your save folder somewhere safe while DF is closed. Setup does not modify saves.");};
   play.Click+=async(s,e)=>await Run(StartGame);
   FormClosing+=(s,e)=>{if(busy){e.Cancel=true;Say("Wait for the current operation to finish.");}else if(viewer!=null&&!viewer.HasExited){e.Cancel=true;Say("Close DF3D first. Dwarf Fortress will remain running.");}};
   Say("Back up saves before playing. Install the bridge once, then Play. Closing the viewer leaves Dwarf Fortress available for saving or recovery.");
  }
  void Check(){if(!acknowledge.Checked)throw new IOException("Back up your saves and check the preview acknowledgement first.");}
  void SaveSettings(){Package.AtomicJson(settings,new Dictionary<string,string>{{"installation",Path.GetFullPath(path.Text)},{"journal",lastJournal}});}
  void Say(string text){status.AppendText(text+Environment.NewLine);Directory.CreateDirectory(Package.Home);File.AppendAllText(Path.Combine(Package.Home,"launcher.log"),DateTime.UtcNow.ToString("o")+" "+text+Environment.NewLine);}
  async Task Run(Func<Task> action){if(busy)return;busy=true;setup.Enabled=play.Enabled=false;try{await action();}catch(Exception ex){Say(ex.Message+(ex is UnauthorizedAccessException ? " Choose a writable DF installation or run setup with the required Windows permissions." : ""));}finally{busy=false;setup.Enabled=play.Enabled=true;}}
  static ProcessStartInfo StartInfo(string exe,string args,string cwd){return new ProcessStartInfo(exe,args){WorkingDirectory=cwd,UseShellExecute=false};}
  async Task<string> Command(string installation,string command){var p=StartInfo(Path.Combine(installation,"hack","dfhack-run.exe"),command,installation);p.CreateNoWindow=true;p.RedirectStandardOutput=true;p.RedirectStandardError=true;p.EnvironmentVariables["DFHACK_PORT"]=commandPort.ToString();using(var proc=Process.Start(p)){var output=proc.StandardOutput.ReadToEndAsync();var error=proc.StandardError.ReadToEndAsync();if(!await Task.Run(()=>proc.WaitForExit(4000))){proc.Kill();throw new IOException("DFHack command timed out");}string result=await output+await error;if(proc.ExitCode!=0)throw new IOException(result.Trim());return result;}}
  async Task GuardAudio(){
   string folder=Path.Combine(Package.Home,"audio",Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);string statusFile=Path.Combine(folder,"status");
   string args="--guard "+viewer.Id+" "+viewer.StartTime.ToFileTimeUtc()+" "+game.Id+" "+game.StartTime.ToFileTimeUtc()+" \""+statusFile+"\" \""+Path.Combine(folder,"stop")+"\"";
   var info=StartInfo(Package.Inside(root,"helpers/audio_guard.exe"),args,folder);info.CreateNoWindow=true;var guard=Process.Start(info);
   var until=DateTime.UtcNow.AddSeconds(15);while(!File.Exists(statusFile)&&!guard.HasExited&&DateTime.UtcNow<until)await Task.Delay(100);
   if(!File.Exists(statusFile)||File.ReadAllText(statusFile).Trim()!="READY")Say("Native audio takeover was not confirmed. Check Windows Volume Mixer. "+folder);
  }
  async Task StartGame(){
   Check();Package.ValidateGame(path.Text,manifest);string installation=Path.GetFullPath(path.Text);
   foreach(var f in manifest.files.Where(x=>x.path.StartsWith(manifest.bridgeRoot+"/",StringComparison.Ordinal))){string installed=Package.Inside(installation,f.path.Substring(manifest.bridgeRoot.Length+1));if(!File.Exists(installed)||!Package.HashFile(installed).Equals(f.sha256,StringComparison.OrdinalIgnoreCase))throw new IOException("Bridge files differ from this preview. Close DF and run Set up bridge.");}
   if(viewer!=null&&!viewer.HasExited)throw new IOException("DF3D is already running.");
   var running=Process.GetProcessesByName("Dwarf Fortress");if(running.Length>1)throw new IOException("Close extra DF instances before playing.");
   commandPort=5000;
   if(running.Length==1){string config=Path.Combine(installation,"dfhack-config","remote-server.json");if(File.Exists(config)){var remote=Package.Json.Deserialize<Dictionary<string,object>>(File.ReadAllText(config));if(remote.ContainsKey("port"))commandPort=Convert.ToInt32(remote["port"]);if(commandPort<1||commandPort>65535)throw new IOException("Invalid DFHack port");}game=running[0];if(!string.Equals(game.MainModule.FileName,Path.Combine(installation,"Dwarf Fortress.exe"),StringComparison.OrdinalIgnoreCase))throw new IOException("A different Dwarf Fortress installation is running.");}
   else {var si=StartInfo(Path.Combine(installation,"Dwarf Fortress.exe"),"",installation);si.EnvironmentVariables["DFHACK_DISABLE_CONSOLE"]="1";si.EnvironmentVariables["DFHACK_PORT"]="5000";game=Process.Start(si);}
   Say("Waiting for Dwarf Fortress. Its window remains available if the viewer fails.");
   string lastError="";bool ready=false;var deadline=DateTime.UtcNow.AddSeconds(120);while(DateTime.UtcNow<deadline){if(game.HasExited)throw new IOException("Dwarf Fortress exited before the bridge was ready.");try{await Command(installation,"enable df3d");string result=await Command(installation,"df3d status");if(Regex.IsMatch(result,@"mirroring enabled:\s+yes")){ready=true;break;}}catch(IOException ex){lastError=ex.Message;}await Task.Delay(500);}
   if(!ready)throw new IOException("Bridge did not become ready. DF was left open; inspect its window and diagnostics. "+lastError);
   SaveSettings();string logs=Path.Combine(Package.Home,"logs");Directory.CreateDirectory(logs);
   var launch=StartInfo(Package.Inside(root,manifest.viewerExecutable),"--log-file \""+Path.Combine(logs,"viewer-"+DateTime.Now.ToString("yyyyMMdd-HHmmss")+".log")+"\"",Path.GetDirectoryName(Package.Inside(root,manifest.viewerExecutable)));
   foreach(string key in launch.EnvironmentVariables.Keys.Cast<string>().Where(x=>x.StartsWith("DF3D_")).ToArray())launch.EnvironmentVariables.Remove(key);
   launch.EnvironmentVariables["DF3D_DF_PATH"]=installation;launch.EnvironmentVariables["DF3D_PROFILE"]="off";launch.EnvironmentVariables["DF3D_RELEASE"]="1";
   viewer=Process.Start(launch);await GuardAudio();Say("DF3D launched. There is no session time limit. Closing this launcher never terminates DF.");
  }
 }
 public static class Program {
  [STAThread] public static int Main(string[] args){try{Directory.CreateDirectory(Package.Home);if(args.Length>0&&args[0]=="--extract-only"){if(args.Length!=2)return 2;Package.Extract(args[1]);return 0;}if(args.Length>0&&args[0]=="--self-test"){SelfTest();return 0;}Application.EnableVisualStyles();Application.SetCompatibleTextRenderingDefault(false);bool created;using(var mutex=new System.Threading.Mutex(true,@"Local\DF3D.ReleaseLauncher",out created)){if(!created){MessageBox.Show("DF3D launcher is already open.");return 1;}Application.Run(new Launcher(Package.Extract()));}return 0;}catch(Exception ex){File.AppendAllText(Path.Combine(Package.Home,"launcher.log"),ex.ToString()+Environment.NewLine);if(args.Length==0)MessageBox.Show(ex.Message,"DF3D setup");return 1;}}
  static void InstallationTests(string temp) {
   string source=Path.Combine(temp,"source"), dest=Path.Combine(temp,"game");Directory.CreateDirectory(Path.Combine(source,"bridge"));Directory.CreateDirectory(Path.Combine(dest,"data","vanilla"));
   using(var pe=new BinaryWriter(File.Create(Path.Combine(dest,"Dwarf Fortress.exe")))){pe.Write((ushort)0x5a4d);pe.BaseStream.Position=0x3c;pe.Write(128);pe.BaseStream.Position=128;pe.Write((uint)0x4550);pe.Write((ushort)0);pe.Write((ushort)0);pe.Write((uint)1234);}
   File.WriteAllText(Path.Combine(source,"bridge","test.dll"),"new");File.WriteAllText(Path.Combine(dest,"test.dll"),"original");
   File.WriteAllText(Path.Combine(source,"bridge","added.dll"),"added");
   var manifest=new Manifest {bridgeRoot="bridge",dwarfFortress=new GameVersion {peTimestamp=1234},files=new List<PayloadFile>()};
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
