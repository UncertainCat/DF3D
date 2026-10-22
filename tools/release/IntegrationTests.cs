using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using DF3D.Release;

// Version tracking intentionally trusts marked installations, including user modifications.
public static class IntegrationTests {
 static void Require(bool value,string message){if(!value)throw new Exception(message);}
 static void Write(string root,string path,string value){string file=Path.Combine(root,path);Directory.CreateDirectory(Path.GetDirectoryName(file));File.WriteAllText(file,value);}
 static void Refused(string game,Manifest manifest,string reason){bool refused=false;try{Package.ValidateDfhack(game,manifest);}catch(IOException){refused=true;}Require(refused,reason);}
 public static void Run(string temp){
  string game=Path.Combine(temp,"version game"),source=Path.Combine(temp,"version payload");
  Directory.CreateDirectory(game);
  var manifest=new Manifest{version="0.1.0-rc.9",bridgeRoot="bridge",dwarfFortress=new GameVersion{peTimestamp=1234},files=new List<PayloadFile>()};
  Require(Package.ValidateDfhack(game,manifest)=="clean","Clean install refused");
  Write(game,"hack/dfhack.dll","unmarked");
  Refused(game,manifest,"Unmarked DFHack accepted");
  Package.AtomicJson(Path.Combine(game,Package.VersionFile),new InstalledVersion{formatVersion=1,version=manifest.version});
  Require(Package.ValidateDfhack(game,manifest)=="current","Matching version refused");
  Write(game,"hack/dfhack.dll","user modified core");Write(game,"dfhack.dll","extra binary");
  Write(game,"hack/plugins/custom.dll","user plugin");
  Require(Package.ValidateDfhack(game,manifest)=="current","Marked user changes were rejected");
  File.Delete(Path.Combine(game,"hack/dfhack.dll"));
  Require(Package.ValidateDfhack(game,manifest)=="current","Marker unexpectedly verified DLL completeness");
  Package.AtomicJson(Path.Combine(game,Package.VersionFile),new InstalledVersion{formatVersion=1,version="0.1.0-rc.8"});
  Require(Package.ValidateDfhack(game,manifest)=="update","Different version did not request update");
  Write(game,Package.VersionFile,"broken");Refused(game,manifest,"Malformed marker accepted");
  Package.AtomicJson(Path.Combine(game,Package.VersionFile),new InstalledVersion{formatVersion=99,version=manifest.version});
  Refused(game,manifest,"Unknown marker format accepted");
  File.Delete(Path.Combine(game,Package.VersionFile));
  string receipt=Path.Combine(Package.Home,"backups","unmarked-test","transaction.json");
  Package.AtomicJson(receipt,new Transaction{destination=game,complete=true});
  Refused(game,manifest,"An old receipt bypassed the required version marker");
  File.Delete(receipt);
  // Real install/restore transitions keep version publication in the file transaction.
  File.Delete(Path.Combine(game,"dfhack.dll"));File.Delete(Path.Combine(game,"hack/plugins/custom.dll"));
  Directory.CreateDirectory(Path.Combine(game,"data/vanilla"));
  using(var pe=new BinaryWriter(File.Create(Path.Combine(game,"Dwarf Fortress.exe")))){pe.Write((ushort)0x5a4d);pe.BaseStream.Position=0x3c;pe.Write(128);pe.BaseStream.Position=128;pe.Write((uint)0x4550);pe.Write((ushort)0);pe.Write((ushort)0);pe.Write((uint)1234);}
  Write(source,"bridge/hack/dfhack.dll","bundled core");
  manifest.files.Add(new PayloadFile{path="bridge/hack/dfhack.dll",sha256=Package.HashFile(Path.Combine(source,"bridge/hack/dfhack.dll"))});
  string first=Package.Install(source,manifest,game);
  Require(Package.ValidateDfhack(game,manifest)=="current","Install did not publish version");
  Require(Package.Install(source,manifest,game)==null,"Identical setup was not a no-op");
  manifest.version="0.1.0-rc.10";
  string second=Package.Install(source,manifest,game);
  var transaction=Package.Json.Deserialize<Transaction>(File.ReadAllText(second));
  Require(transaction.changes.Count==1&&transaction.changes[0].relative==Package.VersionFile,"Version-only update rewrote payload");
  Require(Package.ValidateDfhack(game,manifest)=="current","Updated version missing");
  Package.Restore(second);
  Require(Package.ValidateDfhack(game,manifest)=="update","Restore did not recover old version");
  Package.Restore(first);
  Require(!File.Exists(Path.Combine(game,Package.VersionFile)),"Uninstall left version marker");
 }
}
