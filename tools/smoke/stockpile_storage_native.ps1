param([string]$CloneEvidence='build/native-save-effects-20260930-081415',[switch]$FarmDiscovery,[switch]$FarmFertilization,[switch]$FarmFertilizationProgress,[ValidateSet('none','forbid','dump')][string]$FarmItemAction='none',[switch]$FarmItemActionProgress,[switch]$FarmItemTransfer,[switch]$FarmItemTransferStockpile,[switch]$FarmArtwork,[switch]$FarmResize,[switch]$FarmScroll,[switch]$FarmHeader,[switch]$FarmContentsCaptions,[switch]$FarmItemDescriptionLayout,[switch]$FarmItemRelationships,[switch]$FarmItemCarriers,[switch]$FarmItemCarrierArt,[switch]$PickerResize,[switch]$Repaint,[switch]$Links,[switch]$Rename,[switch]$ZoneRename,[switch]$ZoneGather,[switch]$ZoneDefaults,[switch]$MultiDiscovery,[switch]$ZoneOwner,[switch]$ZoneAnimals,[switch]$ZoneSquads,[switch]$LocationSupplies,[switch]$LocationNames,[switch]$RecognitionOnly,[ValidateSet("promote","empty","first","new","reusehigh","actionreusehigh","eligibility","thoughts","petitions","agreements","positionhigh","positionnew","actionpromote","actionnew","actionfirst","actionempty","actionpetitions","waiver","actionwaiver","firstguidance","specialization","specializationhover","staffindicators","staffindicatorhelp","staffindicatorart","petitiontracker","petitiontrackerpanels","actionstaffindicators","actionspecialization","assignpriest","actionassignpriest","assignmilitarypriest","actionassignmilitarypriest","assigncommandpriest","actionassigncommandpriest","assignspypriest","actionassignspypriest","assignhighpriest","actionassignhighpriest","replacepriest","actionreplacepriest","replaceabsentpriest","actionreplaceabsentpriest","replacesquadpriest","actionreplacesquadpriest","replacemanagerpriest","actionreplacemanagerpriest","replaceaccountantpriest","actionreplaceaccountantpriest","removepriest","removeabsentpriest","actionremoveabsentpriest","removesquadpriest","removemanagerpriest","removeaccountantpriest","actionremovepriest","actionremovesquadpriest","actionremovemanagerpriest","actionremoveaccountantpriest")][string]$RecognitionCase="promote",[string]$RecognitionReference="",[switch]$Tooltips,[switch]$RenameText,[switch]$PaintGestures,[switch]$TilePredicates,[ValidateSet("partial-escape","partial-right","complete-escape","complete-right","brush","eligibility","eligibility-create","eligibility-grow","eligibility-erase","transfer-partial","transfer-full","transfer-create-partial","transfer-create-full","transfer-erase-partial","transfer-erase-full")][string]$GestureCase="partial-escape",[ValidateSet("all","floor","wall","water1","water2","water7","magma1","building1","building2","hidden","ramp","open","all-wall","wall-left","wall-right")][string]$EligibilityCase="all")
$ErrorActionPreference='Stop'
if($FarmItemTransferStockpile -and -not $FarmItemTransfer){throw 'FarmItemTransferStockpile requires FarmItemTransfer'}
if($FarmItemTransfer -and (-not $FarmItemActionProgress -or $FarmItemAction -ne 'forbid')){throw 'FarmItemTransfer requires FarmItemActionProgress and FarmItemAction forbid'}
if($FarmItemActionProgress -and $FarmItemAction -eq 'none'){throw 'FarmItemActionProgress requires FarmItemAction'}
if($FarmItemAction -ne 'none' -and -not $FarmFertilizationProgress){throw 'FarmItemAction requires FarmFertilizationProgress'}
if($FarmFertilization -and -not $FarmDiscovery){throw 'FarmFertilization requires FarmDiscovery'}
if($FarmArtwork -and (-not $FarmDiscovery -or $FarmFertilization)){throw 'FarmArtwork requires FarmDiscovery and excludes FarmFertilization'}
if($FarmResize -and (-not $FarmDiscovery -or $FarmArtwork -or $FarmFertilization)){throw 'FarmResize requires FarmDiscovery and excludes other farm scopes'}
if($FarmScroll -and (-not $FarmDiscovery -or $FarmArtwork -or $FarmFertilization -or $FarmResize)){throw 'FarmScroll requires FarmDiscovery and excludes other farm scopes'}
if($FarmItemCarrierArt -and -not $FarmItemCarriers){throw 'FarmItemCarrierArt requires FarmItemCarriers'}
if($FarmItemCarriers -and (-not $FarmHeader -or $FarmContentsCaptions -or $FarmItemDescriptionLayout -or $FarmItemRelationships)){throw 'FarmItemCarriers requires FarmHeader without other focused contents cases'}
if($FarmItemRelationships -and (-not $FarmHeader -or $FarmContentsCaptions -or $FarmItemDescriptionLayout)){throw 'FarmItemRelationships requires FarmHeader without other focused contents cases'}
if($FarmItemDescriptionLayout -and (-not $FarmHeader -or $FarmContentsCaptions)){throw 'FarmItemDescriptionLayout requires FarmHeader without FarmContentsCaptions'}
if($FarmContentsCaptions -and -not $FarmHeader){throw 'FarmContentsCaptions requires FarmHeader'}
if($FarmHeader -and (-not $FarmDiscovery -or $FarmArtwork -or $FarmFertilization -or $FarmResize -or $FarmScroll)){throw 'FarmHeader requires FarmDiscovery and excludes other farm scopes'}
if($FarmFertilizationProgress -and (-not $FarmDiscovery -or $FarmFertilization -or $FarmArtwork -or $FarmResize -or $FarmScroll -or $FarmHeader)){throw 'FarmFertilizationProgress requires FarmDiscovery and excludes other farm scopes'}
if($FarmDiscovery) {
 foreach($key in $PSBoundParameters.Keys) {
  if($key -notin @('FarmDiscovery','FarmFertilization','FarmFertilizationProgress','FarmItemAction','FarmItemActionProgress','FarmItemTransfer','FarmItemTransferStockpile','FarmArtwork','FarmResize','FarmScroll','FarmHeader','FarmContentsCaptions','FarmItemDescriptionLayout','FarmItemRelationships','FarmItemCarriers','FarmItemCarrierArt','CloneEvidence')){throw 'FarmDiscovery is a separate native scope'}
 }
}
if($RecognitionCase -ne 'promote' -and -not $RecognitionOnly){throw 'RecognitionCase requires RecognitionOnly'}
if($RecognitionOnly -and -not $LocationNames){throw 'RecognitionOnly requires LocationNames'}
if($LocationNames -and ($LocationSupplies -or $ZoneSquads -or $ZoneAnimals -or $ZoneOwner -or $MultiDiscovery -or $ZoneDefaults -or $ZoneGather -or $Rename -or $ZoneRename -or $Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates)){throw 'LocationNames is a separate native scope'}
if($LocationSupplies -and ($ZoneSquads -or $ZoneAnimals -or $ZoneOwner -or $MultiDiscovery -or $ZoneDefaults -or $ZoneGather -or $Rename -or $ZoneRename -or $Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates)){throw 'LocationSupplies is a separate native scope'}
if($ZoneSquads -and ($ZoneAnimals -or $ZoneOwner -or $MultiDiscovery -or $ZoneDefaults -or $ZoneGather -or $Rename -or $ZoneRename -or $Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates)){throw 'ZoneSquads is a separate native scope'}
if($ZoneAnimals -and ($ZoneOwner -or $MultiDiscovery -or $ZoneDefaults -or $ZoneGather -or $Rename -or $ZoneRename -or $Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates)){throw 'ZoneAnimals is a separate native scope'}
if($ZoneOwner -and ($MultiDiscovery -or $ZoneDefaults -or $ZoneGather -or $Rename -or $ZoneRename -or $Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates)){throw 'ZoneOwner is a separate native scope'}
if($MultiDiscovery -and ($ZoneDefaults -or $ZoneGather -or $Rename -or $ZoneRename -or $Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates)){throw 'MultiDiscovery is a separate native scope'}
if($ZoneDefaults -and ($ZoneGather -or $Rename -or $ZoneRename -or $Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates)){throw 'ZoneDefaults is a separate native scope'}
if($ZoneGather -and ($Rename -or $ZoneRename -or $Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates)){throw 'ZoneGather is a separate native settings scope'}
if($ZoneRename) {
 if($Repaint -or $Links -or $Tooltips -or $RenameText -or $PaintGestures -or $TilePredicates){throw 'ZoneRename is a separate native rename scope'}
 $Rename=$true
}
if($GestureCase -eq 'eligibility-create' -and $EligibilityCase -eq 'all'){throw 'Creation cases require a fresh owned session per EligibilityCase'}
if($PickerResize -and -not ($ZoneOwner -or $ZoneAnimals -or $ZoneDefaults)){throw "PickerResize requires ZoneOwner, ZoneAnimals or ZoneDefaults"}
$repo=(Split-Path (Split-Path $PSScriptRoot -Parent) -Parent).Replace('\','/')
$env:Path='C:/msys64/mingw64/bin;'+$env:Path
$dfPath='C:/Program Files (x86)/Steam/steamapps/common/Dwarf Fortress'
Import-Module "$repo/tools/smoke/Df3dLane.psm1" -Force
$prior=if([IO.Path]::IsPathRooted($CloneEvidence)){$CloneEvidence}else{Join-Path $repo $CloneEvidence}
$clone=(Get-Content "$prior/clone-path.txt" -Raw).Trim()
$expected=(Get-Content "$prior/clone-manifest.txt" -Raw).TrimEnd("`r","`n")
function Manifest {
 return (@(Get-ChildItem -LiteralPath $clone -Recurse -File | ForEach-Object {
  $_.FullName.Substring($clone.Length).TrimStart('\','/')+' '+(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
 } | Sort-Object) -join "`n")
}
if((Manifest) -cne $expected){throw 'Owned source differs from verified manifest'}
$scope=if($FarmDiscovery){'farm-discovery'}elseif($RecognitionOnly){"location-recognition-$RecognitionCase"}elseif($LocationNames){'location-names'}elseif($LocationSupplies){'location-supplies'}elseif($ZoneSquads){'zone-squads'}elseif($ZoneAnimals){'zone-animals'}elseif($ZoneOwner){'zone-owner'}elseif($MultiDiscovery){'multi-discovery'}elseif($ZoneDefaults){'zone-defaults'}elseif($ZoneGather){'zone-gather'}elseif($ZoneRename){'zone-rename'}elseif($RenameText){'rename-text'}elseif($Tooltips){'tooltips'}elseif($Links){'links'}elseif($PaintGestures){"gestures-$GestureCase-$EligibilityCase"}elseif($Repaint){'repaint'}else{'input'}
$out="$repo/build/stockpile-storage-native-$scope-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
if($PickerResize){Set-Content -LiteralPath "$out/picker-resize" -Value 1 -Encoding ASCII}
if($FarmDiscovery){Set-Content -LiteralPath "$out/farm-discovery" -Value 1 -Encoding ASCII}
if($FarmItemCarriers){Set-Content -LiteralPath "$out/farm-item-carriers" -Value 1 -Encoding ASCII}
if($FarmItemRelationships){Set-Content -LiteralPath "$out/farm-item-relationships" -Value 1 -Encoding ASCII}
if($FarmItemDescriptionLayout){Set-Content -LiteralPath "$out/farm-item-description-layout" -Value 1 -Encoding ASCII}
if($FarmContentsCaptions){Set-Content -LiteralPath "$out/farm-contents-captions" -Value 1 -Encoding ASCII}
if($FarmHeader){Set-Content -LiteralPath "$out/farm-header" -Value 1 -Encoding ASCII}
if($FarmScroll){Set-Content -LiteralPath "$out/farm-scroll" -Value 1 -Encoding ASCII}
if($FarmResize){Set-Content -LiteralPath "$out/farm-resize" -Value 1 -Encoding ASCII}
if($FarmArtwork){Set-Content -LiteralPath "$out/farm-artwork" -Value 1 -Encoding ASCII}
if($FarmItemAction -ne 'none'){Set-Content -LiteralPath "$out/farm-item-action" -Value $FarmItemAction -Encoding ASCII}
if($FarmItemTransferStockpile){Set-Content -LiteralPath "$out/farm-item-transfer-stockpile" -Value 1 -Encoding ASCII}
if($FarmItemTransfer){Set-Content -LiteralPath "$out/farm-item-transfer" -Value 1 -Encoding ASCII}
if($FarmItemActionProgress){Set-Content -LiteralPath "$out/farm-item-action-progress" -Value 1 -Encoding ASCII}
if($FarmFertilizationProgress){Set-Content -LiteralPath "$out/farm-fertilization-progress" -Value 1 -Encoding ASCII}
if($FarmFertilization){Set-Content -LiteralPath "$out/farm-fertilization" -Value 1 -Encoding ASCII}
if($RecognitionCase -in @('actionspecialization','actionassignpriest','actionassignhighpriest','actionassignmilitarypriest','actionassigncommandpriest','actionassignspypriest') -or $RecognitionCase -like 'actionreplace*' -or $RecognitionCase -like 'actionremove*' -or $RecognitionCase -in @('thoughts','agreements','positionhigh','positionnew','actionpromote','actionnew','actionfirst','actionempty','actionpetitions','actionwaiver','actionreusehigh')) {
 if(-not (Test-Path -LiteralPath $RecognitionReference)){throw 'Recognition comparison requires a native result.json reference'}
 # Screen rows in the raw capture contain CP437. Retain only UTF-8 semantic
 # observations and reject any replacement character in those retained fields.
 $referenceNormalizer=@'
import json,sys
from pathlib import Path
source=json.loads(Path(sys.argv[1]).read_bytes().decode('utf-8',errors='replace'))
data={'success':source['success'],'records':[{k:r[k] for k in ('recognition','holder','new_events','selected','promotion_rng','units','changed') if k in r} for r in source['records']]}
text=json.dumps(data,ensure_ascii=True)
assert '\\ufffd' not in text, 'Invalid UTF-8 in semantic reference'
Path(sys.argv[2]).write_text(text,encoding='ascii')
'@
 & python -c $referenceNormalizer $RecognitionReference "$out/recognition-reference.json"
 if($LASTEXITCODE -ne 0){throw 'Failed to normalize recognition reference'}
 Set-Content -LiteralPath "$out/recognition-reference" -Value "$out/recognition-reference.json" -Encoding ASCII
}
if($RecognitionOnly){Set-Content -LiteralPath "$out/recognition-only" -Value 1 -Encoding ASCII;Set-Content -LiteralPath "$out/recognition-case" -Value $RecognitionCase -Encoding ASCII}
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Drawing;
public static class Shot {
  [DllImport("user32.dll")] public static extern IntPtr SetThreadDpiAwarenessContext(IntPtr value);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X,Y; }
  [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
  delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] static extern IntPtr OpenDesktop(string n, uint f, bool i, uint access);
  [DllImport("user32.dll")] static extern bool EnumDesktopWindows(IntPtr d, EnumProc fn, IntPtr l);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
  [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr d);
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h,System.Text.StringBuilder s,int n);
  [DllImport("user32.dll",EntryPoint="PostMessageW",CharSet=CharSet.Unicode,SetLastError=true)]
  static extern bool PostMessage(IntPtr h,uint message,IntPtr w,IntPtr l);
  public static void KitchenWheel(IntPtr h,int x,int y,int delta,bool shift) {
   var point=new POINT { X=x,Y=y };ClientToScreen(h,ref point);
   if(!PostMessage(h,0x20A,(IntPtr)((delta<<16)|(shift?4:0)),(IntPtr)((point.Y<<16)|(point.X&65535)))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  }
  public static void Text(IntPtr h,string text) {
   foreach(char c in text) {
    if(!PostMessage(h,0x102,(IntPtr)c,IntPtr.Zero)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    System.Threading.Thread.Sleep(40);
   }
  }
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
  public static void Resize(IntPtr h,int width,int height) {
   RECT outer,client;GetWindowRect(h,out outer);GetClientRect(h,out client);
   if(!SetWindowPos(h,IntPtr.Zero,0,0,width+(outer.R-outer.L)-(client.R-client.L),height+(outer.B-outer.T)-(client.B-client.T),0x16))throw new Exception("Resize failed");
  }
  public static void Key(IntPtr h,int key,int scan) {
   long down=1L+((long)scan<<16),up=down+0xc0000000L;
   if(!PostMessage(h,0x100,(IntPtr)key,(IntPtr)down)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(40);
   if(!PostMessage(h,0x101,(IntPtr)key,(IntPtr)up)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);
  }
  public static void Modifier(IntPtr h,int key,int scan,bool down) {
   if(!PostMessage(h,down?0x100U:0x101U,(IntPtr)key,(IntPtr)(1L+((long)scan<<16)+(down?0L:0xc0000000L)))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);
  }
  public static void ControlKey(IntPtr h,int key,int scan) {
   if(!PostMessage(h,0x100,(IntPtr)17,(IntPtr)(1L+(29L<<16)))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);Key(h,key,scan);
   if(!PostMessage(h,0x101,(IntPtr)17,(IntPtr)(1L+(29L<<16)+0xc0000000L))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);
  }
  public static void ControlF(IntPtr h) {
   if(!PostMessage(h,0x100,(IntPtr)17,(IntPtr)(1L+(29L<<16)))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);
   Key(h,70,33);
   if(!PostMessage(h,0x101,(IntPtr)17,(IntPtr)(1L+(29L<<16)+0xc0000000L))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);
  }
  public static void ControlC(IntPtr h) {
   if(!PostMessage(h,0x100,(IntPtr)17,(IntPtr)(1L+(29L<<16)))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);
   Key(h,67,46);
   if(!PostMessage(h,0x101,(IntPtr)17,(IntPtr)(1L+(29L<<16)+0xc0000000L))) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);
  }
  public static void RightClick(IntPtr h) {
   IntPtr point=(IntPtr)(800+(700<<16));
   if(!PostMessage(h,0x204,(IntPtr)2,point)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(40);
   if(!PostMessage(h,0x205,IntPtr.Zero,point)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
   System.Threading.Thread.Sleep(80);
  }
  public static string Windows="";
  public static IntPtr Find(uint pid) {
    IntPtr result=IntPtr.Zero, desk=OpenDesktop("df3d_hidden",0,false,0x41);
    if(desk==IntPtr.Zero) throw new Exception("Hidden desktop unavailable");
    try { EnumDesktopWindows(desk,delegate(IntPtr h,IntPtr l){uint p;GetWindowThreadProcessId(h,out p);RECT r;GetClientRect(h,out r);if(p==pid){var title=new System.Text.StringBuilder(512);GetWindowText(h,title,512);Windows+=title.ToString()+" "+(r.R-r.L)+"x"+(r.B-r.T)+";";if(title.ToString().Contains("Dwarf Fortress") && r.R-r.L>500 && r.B-r.T>400){result=h;}}return true;},IntPtr.Zero); }
    finally {CloseDesktop(desk);}return result;
  }
  public static string Capture(IntPtr h, string path) {
    RECT r; GetClientRect(h, out r); int w = r.R - r.L, hh = r.B - r.T;
    if (w <= 0 || hh <= 0) return "empty client rect";
    using (var bmp = new Bitmap(w, hh)) {
      using (var g = Graphics.FromImage(bmp)) { IntPtr dc = g.GetHdc(); PrintWindow(h, dc, 3); g.ReleaseHdc(dc); }
      long sum = 0; for (int i = 0; i < 400; i++) { var c = bmp.GetPixel((i * 37) % w, (i * 53) % hh); sum += c.R + c.G + c.B; }
      if (sum > 0) { bmp.Save(path, System.Drawing.Imaging.ImageFormat.Png); return "printwindow " + w + "x" + hh; }
    }
    throw new Exception("Empty PrintWindow capture");
  }
}
"@

$entered=$false;$summary='failed'
try {
 Enter-Df3dLane -DfPath $dfPath -Port 5010;$entered=$true
 Get-FileHash "$dfPath/hack/plugins/df3d.plug.dll","$repo/tools/smoke/stockpile_storage_native.lua","$repo/tools/smoke/areas-multi-discovery-native.lua","$repo/tools/smoke/farm-native.lua","$repo/tools/smoke/farm-scroll-native.lua","$repo/tools/smoke/farm-header-native.lua","$repo/tools/smoke/farm-worker-fixture.lua","$repo/tools/smoke/farm-contents-native.lua","$repo/tools/smoke/farm-contents-captions-native.lua","$repo/tools/smoke/farm-item-description-layout-native.lua","$repo/tools/smoke/farm-item-relationships-native.lua","$repo/tools/smoke/farm-item-carriers-native.lua","$repo/bridge/plugin/production.lua","$repo/tools/smoke/areas-owner-native.lua","$repo/tools/smoke/areas-animals-native.lua",$PSCommandPath | ConvertTo-Json | Set-Content "$out/capture-inputs.json"
 Set-DfPrefs;Install-DfMenuStartup -DfPath $dfPath
 $owned=Start-Df3d -DfPath $dfPath
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'Source load failed'}
 $repaintArg=if($Repaint -or $PaintGestures){'true'}else{'false'}
 $linksArg=if($Links){'true'}else{'false'}
 $predicateArg=if($TilePredicates){'true'}else{'false'}
 $gestureArg=if($PaintGestures){"'$GestureCase'"}else{'false'}
 $r=Invoke-DfhackRaw -CommandArgs @('lua',"df.global.d_init.feature.autosave=df.d_init_autosave.NONE;assert(loadfile([==[$repo/tools/smoke/stockpile_storage_native.lua]==]))([==[$out]==],$repaintArg,$gestureArg,'$EligibilityCase',$predicateArg,$linksArg,$($Rename.ToString().ToLower()),$($Tooltips.ToString().ToLower()),$($RenameText.ToString().ToLower()),$($ZoneRename.ToString().ToLower()),$($ZoneGather.ToString().ToLower()),$($ZoneDefaults.ToString().ToLower()),$($MultiDiscovery.ToString().ToLower()),$($ZoneOwner.ToString().ToLower()),$($ZoneAnimals.ToString().ToLower()),$($ZoneSquads.ToString().ToLower()),$($LocationSupplies.ToString().ToLower()),$($LocationNames.ToString().ToLower()))")
 $r | ConvertTo-Json | Set-Content "$out/native.log"
 if($r.ExitCode -ne 0 -or ($r.Output -join "`n") -notmatch 'STOCKPILE_STORAGE_STARTED'){throw 'Native capture start failed'}
 $limit=(Get-Date).AddSeconds(600)
 while(-not(Test-Path "$out/result.json") -and (Get-Date) -lt $limit){
  if($owned.HasExited){throw 'Owned DF exited before the native capture completed'}
  if(($env:DF3D_JUSTICE_CASE_RESIZE -eq '1' -or $env:DF3D_JUSTICE_ROSTER_RESIZE -eq '1' -or $env:DF3D_JUSTICE_ROSTER_RETURN -eq '1' -or $env:DF3D_JUSTICE_GRAPH_RESIZE -eq '1' -or $env:DF3D_JUSTICE_SORTS -eq '1' -or $env:DF3D_JUSTICE_CANDIDATES -eq '1' -or $env:DF3D_OBJECTS_LAYOUT -eq '1' -or $env:DF3D_NOBLES_SYMBOL_NAME_RESIZE -eq '1' -or $env:DF3D_NOBLES_SYMBOL_RESIZE -eq '1' -or $env:DF3D_NOBLES_ACCOUNTING -eq '1' -or $env:DF3D_PLACES_LAYOUT -eq '1' -or $env:DF3D_TASKS_LAYOUT -eq '1' -or $env:DF3D_STOCKS_CONTENTS_SCROLL -eq '1' -or $env:DF3D_STOCKS_RESIZE -eq '1' -or $env:DF3D_STOCKS_WHEEL -eq '1' -or $env:DF3D_WORK_DETAILS_MODSORT -eq '1' -or $env:DF3D_WORK_DETAILS_RETENTION -eq '1' -or $env:DF3D_CHORES_LONG_NAME -eq '1' -or $env:DF3D_STONE_USE_NAV -eq '1' -or $env:DF3D_KITCHEN_MODSORT -eq '1' -or $env:DF3D_KITCHEN_NAV -eq '1' -or $env:DF3D_KITCHEN_LAYOUT -eq '1' -or $env:DF3D_KITCHEN_SEARCH -eq '1' -or $env:DF3D_CHORES_LAYOUT -eq '1' -or $env:DF3D_HUNTER_AMMUNITION_LAYOUT -eq '1' -or $ZoneOwner -or $ZoneAnimals -or $ZoneDefaults -or $LocationSupplies -or $LocationNames -or $FarmResize -or $FarmHeader -or $env:DF3D_WORK_ORDER_ARTWORK_RESIZE -eq '1' -or $env:DF3D_WORK_ORDER_LAYOUT -eq '1' -or $env:DF3D_RESIDENTS_QUERY -eq '1' -or $env:DF3D_WORK_DETAILS_QUERY_PROVIDER -eq '1' -or $env:DF3D_WORK_DETAILS_RENAME -eq '1' -or $env:DF3D_WORK_DETAILS_SHORTCUTS -eq '1' -or $env:DF3D_WORK_DETAILS_LAYOUT -eq '1' -or $env:DF3D_RESIDENTS_JOB_ART_RENDER -eq '1') -and (Test-Path "$out/owner-input-request")) {
   $action=(Get-Content "$out/owner-input-request" -Raw).Trim()
   $window=[Shot]::Find($owned.Id)
   switch($action) {
    'down' {[Shot]::Key($window,40,80)}
    'kitchen-shift-down' {[Shot]::Modifier($window,160,42,$true)}
    'kitchen-shift-up' {[Shot]::Modifier($window,160,42,$false)}
    'kitchen-control-down' {[Shot]::Modifier($window,17,29,$true)}
    'kitchen-control-up' {[Shot]::Modifier($window,17,29,$false)}
    'stocks-wheel' {
     $wheel=Get-Content -LiteralPath "$out/kitchen-wheel.json" -Raw | ConvertFrom-Json
     if($env:DF3D_STOCKS_WHEEL -ne '1' -or "$($wheel.x),$($wheel.y)" -notin @('100,130','328,250','600,130','960,250','500,94','20,20') -or $wheel.delta -notin @(-120,120)){throw 'Stocks wheel outside probe bounds'}
     [Shot]::KitchenWheel($window,$wheel.x,$wheel.y,$wheel.delta,$wheel.shift)
    }
    'kitchen-wheel' {
     $wheel=Get-Content -LiteralPath "$out/kitchen-wheel.json" -Raw | ConvertFrom-Json
     if($wheel.x -notin @(200,944,1100) -or $wheel.y -notin @(250,750) -or $wheel.delta -notin @(-120,120)){throw 'Kitchen wheel outside probe bounds'}
     [Shot]::KitchenWheel($window,$wheel.x,$wheel.y,$wheel.delta,$wheel.shift)
    }
    'enter' {[Shot]::Key($window,13,28)}
    'escape' {[Shot]::Key($window,27,1)}
    'control-n' {[Shot]::ControlKey($window,78,49)}
    'control-i' {[Shot]::ControlKey($window,73,23)}
    'control-f' {[Shot]::ControlF($window)}
    'control-c' {[Shot]::ControlC($window)}
    'right-click' {[Shot]::RightClick($window)}
    'limit' {[Shot]::Text($window,('x'*40))}
    'backspace' {[Shot]::Key($window,8,14)}
    'clear' {for($i=0;$i -lt 33;$i++){[Shot]::Key($window,8,14)}}
    'nonascii' {[Shot]::Text($window,([string][char]0x00e9))}
    'ascii' {[Shot]::Text($window,'a')}
    'name-filter-mixed' {[Shot]::Text($window,'a Z09-_.')}
    'justice-search' {
     $inputSpec=Get-Content -LiteralPath "$out/justice-search-input.json" -Raw -Encoding UTF8 | ConvertFrom-Json
     if($inputSpec.clear_count -lt 0 -or $inputSpec.clear_count -gt 128 -or $inputSpec.text.Length -gt 128){throw 'Justice search input exceeds probe bounds'}
     for($i=0;$i -lt $inputSpec.clear_count;$i++){[Shot]::Key($window,8,14)}
     [Shot]::Text($window,[string]$inputSpec.text)
    }
    'residents-search' {
     $inputSpec=Get-Content -LiteralPath "$out/residents-search-input.json" -Raw -Encoding UTF8 | ConvertFrom-Json
     if($inputSpec.clear_count -lt 0 -or $inputSpec.clear_count -gt 128 -or $inputSpec.text.Length -gt 128){throw 'Residents search input exceeds probe bounds'}
     for($i=0;$i -lt $inputSpec.clear_count;$i++){[Shot]::Key($window,8,14)}
     [Shot]::Text($window,[string]$inputSpec.text)
    }
    'name-resize-small' {[Shot]::Resize($window,960,600)}
    'name-resize-medium' {[Shot]::Resize($window,1200,720)}
    'name-resize-minimum' {[Shot]::Resize($window,640,480)}
    'name-resize-wide' {[Shot]::Resize($window,1600,900)}
    'name-resize-default' {[Shot]::Resize($window,1200,800)}
    default {throw "Unknown owner input action: $action"}
   }
   Remove-Item -LiteralPath "$out/owner-input-request"
   'ok' | Set-Content "$out/owner-input-ack"
  }
  if(Test-Path "$out/shot") {
   $name=(Get-Content "$out/shot" -Raw).Trim()
   if(-not(Test-Path "$out/ack-$name")) {
    if(($env:DF3D_JUSTICE_WIRE -eq '1' -and $name -eq 'justice-wire') -or ($env:DF3D_OBJECTS_WIRE -eq '1' -and $name -eq 'objects-wire') -or ($env:DF3D_NOBLES_WIRE -eq '1' -and $name -eq 'nobles-wire') -or ($env:DF3D_PLACES_WIRE -eq '1' -and $name -eq 'places-wire') -or ($env:DF3D_TASKS_WIRE -eq '1' -and $name -eq 'tasks-wire') -or ($env:DF3D_STOCKS_WIRE -eq '1' -and $name -eq 'stocks-wire') -or ($env:DF3D_LABOR_LIFECYCLE -eq '1' -and $name -eq 'labor-lifecycle-wire') -or ($env:DF3D_STANDING_AUTOMATION_WIRE -eq '1' -and $name -eq 'standing-automation-wire') -or ($env:DF3D_STONE_USE_WIRE -eq '1' -and $name -eq 'stone-use-wire') -or ($env:DF3D_KITCHEN_WIRE -eq '1' -and $name -eq 'kitchen-wire') -or ($env:DF3D_CHORES_WIRE -eq '1' -and $name -eq 'chores-wire') -or ($env:DF3D_HUNTER_AMMUNITION_WIRE -eq '1' -and $name -eq 'hunter-ammunition-wire') -or (($env:DF3D_STANDING_ORDERS_WIRE -eq '1' -or $env:DF3D_STANDING_ORDERS_CATEGORY_WIRE -eq '1' -or $env:DF3D_STANDING_ORDERS_EXTENDED_WIRE -eq '1') -and $name -eq 'standing-orders-wire') -or ($env:DF3D_WORK_DETAILS_FAULT_WIRE -eq '1' -and $name -eq 'work-details-fault-wire') -or ($env:DF3D_WORK_DETAILS_RENAME_WIRE -eq '1' -and $name -eq 'work-details-rename-wire') -or ($env:DF3D_WORK_DETAILS_DELETE_WIRE -eq '1' -and $name -eq 'work-details-delete-wire') -or ($env:DF3D_WORK_DETAILS_SETTINGS_WIRE -eq '1' -and $name -match '^work-details-settings-wire-(normal|locked)$') -or ($env:DF3D_WORK_DETAILS_ROWS_WIRE -eq '1' -and $name -eq 'work-details-root') -or ($env:DF3D_WORK_DETAILS_QUERY_WIRE -eq '1' -and $name -eq 'work-details-query') -or ($env:DF3D_RESIDENTS_JOB_SETTINGS_WIRE -eq '1' -and $name -eq 'residents-job-settings') -or ($env:DF3D_RESIDENTS_JOB_ART_WIRE -eq '1' -and $name -eq 'residents-job-art-root') -or ($env:DF3D_RESIDENTS_JOB_PRODUCTION_WIRE -eq '1' -and $name -eq 'residents-job-production-wire') -or ($env:DF3D_WORK_DETAILS_DEFAULTS -eq '1' -and $name -eq 'work-details-defaults-wire') -or ($env:DF3D_WORK_DETAILS_MEMBERSHIP -eq '1' -and $name -eq 'work-details-membership-wire') -or ($env:DF3D_WORK_DETAILS_EDITS -eq '1' -and $name -match '^work-details-edit-[1-4]-wire$')) {
     $env:DF3D_CARRIER_DIRECTORY=$out;$env:DF3D_DF_PATH=$dfPath
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $clientArgs=@('--headless')
     if($env:DF3D_STANDING_ORDERS_RENDER -eq '1' -or $env:DF3D_WORK_DETAILS_RENAME_RENDER -eq '1' -or ($env:DF3D_WORK_DETAILS_RESET_RENDER -eq '1' -and $name -eq 'work-details-edit-4-wire') -or $env:DF3D_RESIDENTS_JOB_ART_RENDER -eq '1' -or $env:DF3D_WORK_DETAILS_RENDER -eq '1' -or $env:DF3D_WORK_DETAILS_SETTINGS_RENDER -eq '1'){$clientArgs=@('--max-fps','30')}
     $clientArgs+=@('--path',"$repo/presentations/godot/project",'--script','res://tests/job_settings_wire_live.gd')
     if($env:DF3D_CHORES_RENDER -eq '1' -or $env:DF3D_HUNTER_AMMUNITION_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/job_settings_wire_live.gd')}
     if($name -eq 'nobles-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/nobles_wire_live.gd')}
     if($name -eq 'nobles-wire' -and $env:DF3D_NOBLES_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/nobles_wire_live.gd')}
     if($name -eq 'nobles-wire' -and $env:DF3D_NOBLES_SCENE -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/nobles_scene_live.gd')}
     if($name -eq 'justice-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/justice_wire_live.gd')}
     if($name -eq 'justice-wire' -and $env:DF3D_JUSTICE_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/justice_wire_live.gd')}
     if($name -eq 'justice-wire' -and $env:DF3D_JUSTICE_SCENE -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/justice_scene_live.gd')}
     if($name -eq 'objects-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/objects_wire_live.gd')}
     if($name -eq 'objects-wire' -and $env:DF3D_OBJECTS_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/objects_wire_live.gd')}
     if($name -eq 'objects-wire' -and $env:DF3D_OBJECTS_SCENE -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/objects_scene_live.gd')}
     if($name -eq 'places-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/places_wire_live.gd')}
     if($name -eq 'places-wire' -and $env:DF3D_PLACES_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/places_wire_live.gd')}
     if($name -eq 'places-wire' -and $env:DF3D_PLACES_SCENE -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/places_scene_live.gd')}
     if($name -eq 'tasks-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/tasks_wire_live.gd')}
     if($name -eq 'tasks-wire' -and $env:DF3D_TASKS_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/tasks_wire_live.gd')}
     if($name -eq 'tasks-wire' -and $env:DF3D_TASKS_SCENE -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/tasks_scene_live.gd')}
     if($name -eq 'stocks-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/stocks_wire_live.gd')}
     if($name -eq 'stocks-wire' -and $env:DF3D_STOCKS_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/stocks_wire_live.gd')}
     if($name -eq 'stocks-wire' -and $env:DF3D_STOCKS_SCENE -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/stocks_scene_live.gd')}
     if($name -eq 'stone-use-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/stone_use_wire_live.gd')}
     if($name -eq 'stone-use-wire' -and $env:DF3D_STONE_USE_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/stone_use_wire_live.gd')}
     if($name -eq 'kitchen-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/kitchen_wire_live.gd')}
     if($name -eq 'kitchen-wire' -and $env:DF3D_KITCHEN_RENDER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/kitchen_wire_live.gd')}
     if($name -eq 'labor-lifecycle-wire'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/labor_lifecycle_wire_live.gd')}
     if($name -eq 'labor-lifecycle-wire' -and $env:DF3D_LABOR_LIFECYCLE_HEADLESS -eq '1'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/labor_lifecycle_wire_live.gd')}
     if($name -eq 'standing-automation-wire'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/standing_automation_wire_live.gd')}
     $client=Start-Process -FilePath $engine -ArgumentList $clientArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/job-settings-wire.stdout.log" -RedirectStandardError "$out/job-settings-wire.stderr.log"
     $null=$client.Handle
     $wireTimeout=if($name -eq 'objects-wire' -and $env:DF3D_OBJECTS_LAYOUT -eq '1'){55000}elseif($name -eq 'kitchen-wire' -and $env:DF3D_KITCHEN_MAIN -eq '1'){115000}else{25000}
     # A rendered multi-family item batch includes graphics initialization and
     # several sheet captures. Keep this bounded separately from wire-only work.
     if($name -eq 'stocks-wire' -and $env:DF3D_STOCKS_RENDER -eq '1' -and $env:DF3D_STOCKS_FURNITURE_SHEETS -eq '1'){$wireTimeout=60000}
     if($name -eq 'justice-wire' -and $env:DF3D_JUSTICE_WIRE_INTERROGATE -eq '1'){$wireTimeout=55000}
     if($name -eq 'justice-wire' -and $env:DF3D_JUSTICE_SCENE -eq '1'){$wireTimeout=115000}
     if($name -eq 'places-wire' -and $env:DF3D_PLACES_SCENE -eq '1'){$wireTimeout=115000}
     if($name -eq 'objects-wire' -and $env:DF3D_OBJECTS_SCENE -eq '1'){$wireTimeout=55000}
     if($name -eq 'objects-wire' -and $env:DF3D_OBJECTS_LIFECYCLE -eq '1'){$wireTimeout=115000}
     if($name -eq 'tasks-wire' -and $env:DF3D_TASKS_SCENE -eq '1'){$wireTimeout=115000}
     if($name -eq 'stocks-wire' -and $env:DF3D_STOCKS_SCENE -eq '1'){$wireTimeout=115000}
     if($name -eq 'stone-use-wire' -and $env:DF3D_STONE_USE_MAIN -eq '1'){$wireTimeout=115000}
     if($name -eq 'standing-automation-wire'){$wireTimeout=115000}
     if($name -eq 'labor-lifecycle-wire'){$wireTimeout=295000}
     if($name -eq 'hunter-ammunition-wire' -and $env:DF3D_HUNTER_AMMUNITION_MAIN -eq '1'){$wireTimeout=115000}
     if($name -eq 'nobles-wire' -and $env:DF3D_NOBLES_SYMBOL_NAME_RESIZE -eq '1'){$wireTimeout=115000}
     if($name -eq 'nobles-wire' -and $env:DF3D_NOBLES_SCENE -eq '1'){$wireTimeout=115000}
     if(-not $client.WaitForExit($wireTimeout)){$client.Kill();$client.WaitForExit();throw 'Job settings wire client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/job-settings-wire-result.json")){throw 'Job settings wire client failed'}
    }
    if($env:DF3D_RESIDENTS_WIRE -eq '1' -and $name -eq 'residents-root') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/residents_query_wire_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/residents-wire.stdout.log" -RedirectStandardError "$out/residents-wire.stderr.log"
     $null=$client.Handle
     if(-not $client.WaitForExit(25000)){$client.Kill();$client.WaitForExit();throw 'Residents wire client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/residents-wire-result.json")){throw 'Residents wire client failed'}
    }
    # Symbol probes allocate native textures; allow their upload/present to
    # settle before PrintWindow. Exact pixel verification below rejects tears.
    if($ZoneSquads){Start-Sleep -Milliseconds 250}
    [Shot]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
    [Shot]::Capture([Shot]::Find($owned.Id),"$out/$name.png") | Out-Null
    if($FarmItemCarriers -and $name -eq 'chest-melt-wire') {
     $env:DF3D_CARRIER_DIRECTORY=$out;$env:DF3D_DF_PATH=$dfPath
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-ContainedProcess -Exe $engine -Arguments "--max-fps 30 --path `"$repo/presentations/godot/project`" --script res://tests/chest_melt_scene_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     $null=$client.Handle
     if(-not $client.WaitForExit(90000)){$client.Kill();$client.WaitForExit();throw 'Melt scene timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/chest-melt-scene-result.json")){throw 'Melt scene client failed'}
    }
    if($FarmItemCarriers -and $name -in @('farm-item-carrier-scene','farm-item-carrier-unit-scene')) {
     $env:DF3D_CARRIER_DIRECTORY=$out;$env:DF3D_DF_PATH=$dfPath
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-ContainedProcess -Exe $engine -Arguments "--max-fps 30 --path `"$repo/presentations/godot/project`" --script res://tests/item_carrier_scene_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     $null=$client.Handle
     if(-not $client.WaitForExit(90000)){$client.Kill();$client.WaitForExit();throw 'Carrier scene timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/carrier-scene-result.json")){throw 'Carrier scene client failed'}
    }
    if($FarmItemCarriers -and $name -eq 'chest-owner-wire') {
     $env:DF3D_CARRIER_DIRECTORY=$out;$env:DF3D_DF_PATH=$dfPath
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-ContainedProcess -Exe $engine -Arguments "--max-fps 30 --path `"$repo/presentations/godot/project`" --script res://tests/chest_scene_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     $null=$client.Handle
     if(-not $client.WaitForExit(90000)){$client.Kill();$client.WaitForExit();throw 'Chest scene client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/chest-scene-result.json")){throw 'Chest scene client failed'}
    }
    if($FarmItemCarriers -and $name -match '^chest-header-wire-(idle|worker|suspended)$') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     if($FarmItemCarrierArt){
      $env:DF3D_DF_PATH=$dfPath
      $client=Start-ContainedProcess -Exe $engine -Arguments "--max-fps 30 --path `"$repo/presentations/godot/project`" --script res://tests/chest_header_art_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     }else{
     $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/chest_header_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     }
     $null=$client.Handle
     if(-not $client.WaitForExit(25000)){$client.Kill();$client.WaitForExit();throw 'Chest header client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/chest-header-wire-result.json")){throw 'Chest header client failed'}
     Copy-Item -LiteralPath "$out/chest-header-wire-result.json" -Destination "$out/$name.json"
    }
    if($FarmItemCarriers -and $name -eq 'farm-chest-contents-wire') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     if($FarmItemCarrierArt){
      $env:DF3D_DF_PATH=$dfPath
      $client=Start-ContainedProcess -Exe $engine -Arguments "--max-fps 30 --path `"$repo/presentations/godot/project`" --script res://tests/chest_contents_art_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     }else{
     $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/chest_contents_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     }
     $null=$client.Handle
     if(-not $client.WaitForExit(25000)){$client.Kill();$client.WaitForExit();throw 'Chest contents client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/chest-contents-result.json")){throw 'Chest contents client failed'}
    }
    if($FarmItemCarriers -and $name -eq 'unit-follow-lifecycle') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/creature_follow_lifecycle_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     $null=$client.Handle
     if(-not $client.WaitForExit(25000)){$client.Kill();$client.WaitForExit();throw 'Unit follow lifecycle client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/unit-follow-lifecycle-result.json")){throw 'Unit follow lifecycle client failed'}
    }
    if($FarmItemCarriers -and $name -match '^unit-follow-wire-') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/creature_follow_wire_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     $null=$client.Handle
     if(-not $client.WaitForExit(25000)){$client.Kill();$client.WaitForExit();throw 'Unit follow client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/unit-follow-wire-result.json")){throw 'Unit follow client failed'}
    }
    if($FarmItemCarriers -and $name -match '^unit-expel-wire-(preview|apply)$') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $env:DF3D_EXPEL_WIRE_PHASE=$Matches[1]
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $waitMs=25000
     if($env:DF3D_UNIT_EXPEL_EFFECT_SCENE -eq '1' -and $env:DF3D_EXPEL_WIRE_PHASE -eq 'apply') {
      $env:DF3D_DF_PATH=$dfPath
      $client=Start-ContainedProcess -Exe $engine -Arguments "--max-fps 30 --path `"$repo/presentations/godot/project`" --script res://tests/creature_expel_scene_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
      $waitMs=90000
     } else {
      $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/creature_expel_wire_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     }
     $null=$client.Handle
     if(-not $client.WaitForExit($waitMs)){$client.Kill();$client.WaitForExit();throw 'Unit Expel client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/$name.json")){throw 'Unit Expel client failed'}
    }
    if($name -in @('work-order-dye-wire','work-order-artwork-wire','work-order-navigation-wire')) {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $env:DF3D_DF_PATH=$dfPath
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-Process -FilePath $engine -ArgumentList @('--max-fps','30','--path',"$repo/presentations/godot/project",'--script',('res://tests/'+$name.Replace('-','_')+'_live.gd')) -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     $null=$client.Handle
     if(-not $client.WaitForExit(60000)){$client.Kill();$client.WaitForExit();throw 'Work order client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/$name-result.json")){throw 'Work order client failed'}
    }
    if($FarmItemCarriers -and ($name -in @('workshop-wire','workshop-order-wire','lever-warning-wire','machinery-wire') -or $name -like 'door-mode-wire-*' -or $name -like 'trap-sheet-wire-*' -or $name -eq 'machinery-contract-wire')) {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $env:DF3D_DOOR_CAPTURE=$name
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $script=if($env:DF3D_TILE_SELECTION_ENGRAVING_ART_RUNTIME -eq '1'){'res://tests/tile_selection_art_wire_live.gd'}elseif($env:DF3D_TILE_SELECTION_ENGRAVING -eq '1' -and $env:DF3D_TILE_SELECTION_SCENE -eq '1'){'res://tests/tile_selection_engraving_scene_live.gd'}elseif($env:DF3D_TILE_SELECTION_ENGRAVING -eq '1'){'res://tests/tile_selection_engraving_wire_live.gd'}elseif($env:DF3D_TILE_SELECTION_UNITS -eq '1' -and $env:DF3D_TILE_SELECTION_SCENE -eq '1'){'res://tests/tile_selection_unit_scene_live.gd'}elseif($env:DF3D_TILE_SELECTION_UNITS -eq '1'){'res://tests/tile_selection_unit_wire_live.gd'}elseif($env:DF3D_TILE_SELECTION_SCENE -eq '1'){'res://tests/tile_selection_scene_live.gd'}elseif($env:DF3D_TILE_SELECTION_RUNTIME -eq '1'){'res://tests/tile_selection_wire_live.gd'}elseif($env:DF3D_WORKSHOP_ORDERS_OVERFLOW -eq '1'){'res://tests/workshop_orders_overflow_scene_live.gd'}elseif($env:DF3D_WORKSHOP_HEADER_QUEUED_RUNTIME -eq '1'){'res://tests/workshop_queued_removal_scene_live.gd'}elseif($env:DF3D_WORKSHOP_CONNECTIONS_MULTI_SCENE -eq '1'){'res://tests/workshop_connections_multi_scene_live.gd'}elseif($env:DF3D_WORKSHOP_CONNECTIONS_SCENE -eq '1'){'res://tests/workshop_connections_scene_live.gd'}elseif($env:DF3D_WORKSHOP_CONNECTIONS_RUNTIME -eq '1'){'res://tests/workshop_connections_wire_live.gd'}elseif($env:DF3D_WORKSHOP_HEADER_RUNTIME -eq '1'){'res://tests/workshop_header_scene_live.gd'}elseif($env:DF3D_WORKSHOP_SHEET_LAYOUT -eq '1'){'res://tests/workshop_sheet_layout_live.gd'}elseif($env:DF3D_WORKSHOP_REACTION_RUNTIME -eq '1'){'res://tests/workshop_reactions_live.gd'}elseif($env:DF3D_WORKSHOP_DYER_RUNTIME -eq '1'){'res://tests/workshop_dyer_live.gd'}elseif($env:DF3D_WORKSHOP_STONE_RUNTIME -eq '1'){'res://tests/workshop_stone_live.gd'}elseif($env:DF3D_WORKSHOP_CLOTHIER_RUNTIME -eq '1' -or $env:DF3D_WORKSHOP_GLASS_RUNTIME -eq '1' -or $env:DF3D_WORKSHOP_CRAFT_RUNTIME -eq '1'){'res://tests/workshop_clothier_live.gd'}elseif($env:DF3D_WORKSHOP_FAMILY_RUNTIME -eq '1'){'res://tests/workshop_families_live.gd'}elseif($env:DF3D_WORKSHOP_FORGE_RUNTIME -eq '1'){'res://tests/workshop_forge_live.gd'}elseif($env:DF3D_WORKSHOP_JOB_CONTROLS -eq '1'){'res://tests/workshop_job_controls_live.gd'}elseif($env:DF3D_WORKSHOP_SELECTOR_LAYOUT -eq '1'){'res://tests/workshop_selector_layout_live.gd'}elseif($name -eq 'workshop-order-wire'){'res://tests/workshop_order_wire_live.gd'}else{'res://tests/workshop_wire_live.gd'}
     if($env:DF3D_TILE_SELECTION_VERMIN -eq '1'){$script='res://tests/tile_selection_vermin_scene_live.gd'}
     $clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script',$script)
     if($env:DF3D_DOOR_CONTROL_RUNTIME -eq '1'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/door_controls_wire_live.gd')}
     if($env:DF3D_PENDING_RUNTIME -eq '1'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_building_wire_live.gd')}
     if($env:DF3D_PENDING_SCENE -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_building_scene_live.gd')}
     if($env:DF3D_PENDING_CONTENTS_RUNTIME -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_contents_scene_live.gd')}
     if($env:DF3D_PENDING_HEADER_ART -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_header_art_scene_live.gd')}
     if($env:DF3D_PENDING_SELECTION -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_selection_scene_live.gd')}
     if($env:DF3D_PENDING_COMPONENT_SELECTION -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_component_selection_scene_live.gd')}
     if($env:DF3D_PENDING_LAYOUT -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_layout_scene_live.gd')}
     if($env:DF3D_PENDING_MAP -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_map_scene_live.gd')}
     if($env:DF3D_PENDING_PROGRESS_RUNTIME -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pending_progress_scene_live.gd')}
     if($env:DF3D_DOOR_HEADER_RUNTIME -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/door_scene_live.gd')}
     if($env:DF3D_FURNITURE_RUNTIME -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/furniture_scene_live.gd')}
     if($env:DF3D_FURNITURE_MAP -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/furniture_map_scene_live.gd')}
     if($env:DF3D_BUILDING_LINKS_WIRE -eq '1'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/building_links_wire_live.gd')}
     if($env:DF3D_LEVER_WIRE -eq '1'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/lever_wire_live.gd')}
     if($env:DF3D_PRESSURE_PLATE_WIRE -eq '1'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/pressure_plate_wire_live.gd')}
     if($env:DF3D_PRESSURE_PLATE_PANEL -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pressure_plate_panel_live.gd')}
     if($env:DF3D_PRESSURE_PLATE_MAP -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/pressure_plate_map_scene_live.gd')}
     if($env:DF3D_LEVER_PROMPT_ART -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/lever_prompt_art_live.gd')}
     if($env:DF3D_LEVER_PANEL -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/lever_panel_live.gd')}
     if($env:DF3D_LEVER_MAP -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/lever_map_scene_live.gd')}
     if($name -eq 'lever-warning-wire'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/lever_warning_scene_live.gd')}
     if($env:DF3D_FLOODGATE_RUNTIME -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/floodgate_scene_live.gd')}
     if($env:DF3D_FLOODGATE_SCROLL_VIEWER -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/floodgate_scroll_scene_live.gd')}
     if($env:DF3D_FLOODGATE_MAP -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/floodgate_map_scene_live.gd')}
     if($env:DF3D_BUILDING_LINKS_ART -eq '1'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/building_links_art_live.gd')}
     if($name -like 'trap-sheet-wire-*'){$clientArgs=@('--max-fps','30','--path',"$repo/presentations/godot/project",'--script','res://tests/trap_sheet_scene_live.gd')}
     if($name -eq 'machinery-contract-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/machinery_contract_wire_live.gd')}
     if($name -eq 'machinery-wire'){$clientArgs=@('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/machinery_wire_live.gd')}
     $client=Start-Process -FilePath $engine -ArgumentList $clientArgs -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     $null=$client.Handle
     $workshopClientTimeout=if($env:DF3D_FURNITURE_GENERIC_DISCOVERY -eq '1'){90000}else{45000}
     if(-not $client.WaitForExit($workshopClientTimeout)){$client.Kill();$client.WaitForExit();throw 'Workshop client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/$name-result.json")){throw 'Workshop client failed'}
    }
    if($FarmItemCarriers -and $name -eq 'unit-header-wire') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/creature_header_wire_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/unit-header-wire.stdout.log" -RedirectStandardError "$out/unit-header-wire.stderr.log"
     $null=$client.Handle
     if(-not $client.WaitForExit(25000)){$client.Kill();$client.WaitForExit();throw 'Unit header client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/unit-header-wire-result.json")){throw 'Unit header client failed'}
    }
    if($FarmItemCarriers -and $name -match '^farm-item-carrier-(container|unit|box|instrument-[0-9]+)-wire$') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     if($FarmItemCarrierArt){
      $env:DF3D_DF_PATH=$dfPath
      $client=Start-ContainedProcess -Exe $engine -Arguments "--max-fps 30 --path `"$repo/presentations/godot/project`" --script res://tests/item_carrier_art_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     }else{
     $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/item_carrier_wire_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     }
     $null=$client.Handle
     if(-not $client.WaitForExit(25000)){$client.Kill();$client.WaitForExit();throw 'Carrier wire client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/carrier-wire-result.json")){throw 'Carrier wire client failed'}
     Copy-Item -LiteralPath "$out/carrier-wire-result.json" -Destination "$out/$name.json"
    }
    # A transient Windows file lock must not abort an otherwise valid capture.
    # Acknowledge only after removal, so the producer cannot publish its next shot.
    for($attempt=0;;$attempt++) {
     try {Remove-Item -LiteralPath "$out/shot" -ErrorAction Stop;break}
     catch {if($attempt -ge 19){throw};Start-Sleep -Milliseconds 50}
    }
    'ok' | Set-Content "$out/ack-$name"
   }
  }
  Start-Sleep -Milliseconds 100
 }
 $result=Get-Content "$out/result.json" -Raw | ConvertFrom-Json
 if(-not $result.success){throw $result.error}
 if($ZoneSquads) {
  & python "$repo/tools/verify_squad_symbol_reference.py" $out --df-path $dfPath *> "$out/symbol-pixels.log"
  if($LASTEXITCODE -ne 0){throw 'Squad symbol pixel verification failed; see symbol-pixels.log'}
 }
 if($RenameText) {
  $samples=@('abc XYZ',("a"+[char]0x00e9+[char]0x03b1+[char]0x4e2d+"b"),"ab`r`ncd`tef",('a'*80),(('a'*18)+[char]0x00e9+'Z'),(('a'*19)+[char]0x00e9+'Z'))
  $observations=@();$index=0
  foreach($text in $samples) {
   $prepare=Invoke-DfhackRaw -CommandArgs @('lua',"local b=df.global.world.buildings.other.STOCKPILE[0];local ui=df.global.game.main_interface;assert(ui.stockpile.cur_bld==b);local g=df.global.gps;g.mouse_x=42;g.mouse_y=6;g.precise_mouse_x=340;g.precise_mouse_y=78;local gui=require('gui');local v=dfhack.gui.getDFViewscreen(true);gui.simulateInput(v,'_MOUSE_L');assert(ui.entering_building_name);for i=1,#b.name do gui.simulateInput(v,'STRING_A000')end;assert(b.name=='' and df.global.pause_state);print('TEXT_READY')")
   if($prepare.ExitCode -ne 0 -or ($prepare.Output -join "`n") -notmatch 'TEXT_READY'){throw 'Name text preparation failed'}
   [Shot]::Text([Shot]::Find($owned.Id),$text)
   Start-Sleep -Milliseconds 500
   $read=Invoke-DfhackRaw -CommandArgs @('lua',"local b=df.global.world.buildings.other.STOCKPILE[0];assert(df.global.pause_state);local bytes={};for i=1,#b.name do bytes[#bytes+1]=b.name:byte(i)end;print('TEXT_RESULT '..require('json').encode{stored=dfhack.df2utf(b.name),bytes=bytes,editing=df.global.game.main_interface.entering_building_name,frame=df.global.world.frame_counter})")
   if($read.ExitCode -ne 0){throw 'Name text read failed'}
   $raw=$read.Output -join "`n";$raw | Add-Content "$out/text-messages.log"
   $start=$raw.IndexOf('TEXT_RESULT ');if($start -lt 0){throw 'Missing name text observation'}
   $observations+=@{typed=$text;message_interval_ms=40;native=($raw.Substring($start+12) | ConvertFrom-Json)}
   [Shot]::Capture([Shot]::Find($owned.Id),"$out/name-text-$index.png") | Out-Null
   $index++
  }
  $observations | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 "$out/text-messages.json"
 }
 $summary='passed'
} catch {$summary='failed '+$_.Exception.Message}
finally {
 try {if($entered){Exit-Df3dLane}} catch {$summary='failed teardown '+$_.Exception.Message}
 try {if((Manifest) -cne $expected){throw 'Source changed'};'Owned source unchanged' | Set-Content "$out/save-preservation.txt"} catch {$summary='failed preservation '+$_.Exception.Message}
 $summary | Set-Content "$out/summary.txt";Write-Output "$summary -- $out"
}
if($summary -ne 'passed'){exit 1}





