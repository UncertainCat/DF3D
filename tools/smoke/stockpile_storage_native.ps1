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
  if(($ZoneOwner -or $ZoneAnimals -or $ZoneDefaults -or $LocationSupplies -or $LocationNames -or $FarmResize -or $FarmHeader) -and (Test-Path "$out/owner-input-request")) {
   $action=(Get-Content "$out/owner-input-request" -Raw).Trim()
   $window=[Shot]::Find($owned.Id)
   switch($action) {
    'down' {[Shot]::Key($window,40,80)}
    'enter' {[Shot]::Key($window,13,28)}
    'escape' {[Shot]::Key($window,27,1)}
    'control-f' {[Shot]::ControlF($window)}
    'control-c' {[Shot]::ControlC($window)}
    'right-click' {[Shot]::RightClick($window)}
    'limit' {[Shot]::Text($window,('x'*40))}
    'backspace' {[Shot]::Key($window,8,14)}
    'clear' {for($i=0;$i -lt 33;$i++){[Shot]::Key($window,8,14)}}
    'nonascii' {[Shot]::Text($window,([string][char]0x00e9))}
    'ascii' {[Shot]::Text($window,'a')}
    'name-filter-mixed' {[Shot]::Text($window,'a Z09-_.')}
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
    # Symbol probes allocate native textures; allow their upload/present to
    # settle before PrintWindow. Exact pixel verification below rejects tears.
    if($ZoneSquads){Start-Sleep -Milliseconds 250}
    [Shot]::SetThreadDpiAwarenessContext([IntPtr](-4)) | Out-Null
    [Shot]::Capture([Shot]::Find($owned.Id),"$out/$name.png") | Out-Null
    if($FarmItemCarriers -and $name -eq 'chest-melt-wire') {
     $env:DF3D_CARRIER_DIRECTORY=$out;$env:DF3D_DF_PATH=$dfPath
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-ContainedProcess -Exe $engine -Arguments "--path `"$repo/presentations/godot/project`" --script res://tests/chest_melt_scene_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     $null=$client.Handle
     if(-not $client.WaitForExit(90000)){$client.Kill();$client.WaitForExit();throw 'Melt scene timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/chest-melt-scene-result.json")){throw 'Melt scene client failed'}
    }
    if($FarmItemCarriers -and $name -eq 'farm-item-carrier-scene') {
     $env:DF3D_CARRIER_DIRECTORY=$out;$env:DF3D_DF_PATH=$dfPath
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-ContainedProcess -Exe $engine -Arguments "--path `"$repo/presentations/godot/project`" --script res://tests/item_carrier_scene_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     $null=$client.Handle
     if(-not $client.WaitForExit(90000)){$client.Kill();$client.WaitForExit();throw 'Carrier scene timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/carrier-scene-result.json")){throw 'Carrier scene client failed'}
    }
    if($FarmItemCarriers -and $name -eq 'chest-owner-wire') {
     $env:DF3D_CARRIER_DIRECTORY=$out;$env:DF3D_DF_PATH=$dfPath
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     $client=Start-ContainedProcess -Exe $engine -Arguments "--path `"$repo/presentations/godot/project`" --script res://tests/chest_scene_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     $null=$client.Handle
     if(-not $client.WaitForExit(90000)){$client.Kill();$client.WaitForExit();throw 'Chest scene client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/chest-scene-result.json")){throw 'Chest scene client failed'}
    }
    if($FarmItemCarriers -and $name -match '^chest-header-wire-(idle|worker|suspended)$') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     if($FarmItemCarrierArt){
      $env:DF3D_DF_PATH=$dfPath
      $client=Start-ContainedProcess -Exe $engine -Arguments "--path `"$repo/presentations/godot/project`" --script res://tests/chest_header_art_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
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
      $client=Start-ContainedProcess -Exe $engine -Arguments "--path `"$repo/presentations/godot/project`" --script res://tests/chest_contents_art_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
     }else{
     $client=Start-Process -FilePath $engine -ArgumentList @('--headless','--path',"$repo/presentations/godot/project",'--script','res://tests/chest_contents_live.gd') -WindowStyle Hidden -PassThru -RedirectStandardOutput "$out/$name.stdout.log" -RedirectStandardError "$out/$name.stderr.log"
     }
     $null=$client.Handle
     if(-not $client.WaitForExit(25000)){$client.Kill();$client.WaitForExit();throw 'Chest contents client timed out; no replay'}
     if($client.ExitCode -ne 0 -or -not (Test-Path "$out/chest-contents-result.json")){throw 'Chest contents client failed'}
    }
    if($FarmItemCarriers -and $name -match '^farm-item-carrier-(container|unit|box|instrument-[0-9]+)-wire$') {
     $env:DF3D_CARRIER_DIRECTORY=$out
     $engine='C:/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe'
     if($FarmItemCarrierArt){
      $env:DF3D_DF_PATH=$dfPath
      $client=Start-ContainedProcess -Exe $engine -Arguments "--path `"$repo/presentations/godot/project`" --script res://tests/item_carrier_art_live.gd --log-file `"$out/$name.godot.log`"" -WorkingDir "$repo/presentations/godot/project"
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





