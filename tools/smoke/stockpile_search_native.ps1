param([string]$CloneEvidence="build/native-save-effects-20260930-081415",[switch]$TruncationWidths,[switch]$TextMessages,[switch]$HistoricalMaterials,[switch]$TextChunks)
$ErrorActionPreference='Stop'
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
$out="$repo/build/stockpile-search-native-$(Get-Date -Format yyyyMMdd-HHmmss)"
New-Item -ItemType Directory -Path $out | Out-Null
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Drawing;
public static class Shot {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
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
  [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr h,out RECT r);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags);
  public static string Resize(IntPtr h,int width,int height) {
   RECT outer,client;GetWindowRect(h,out outer);GetClientRect(h,out client);
   if(!SetWindowPos(h,IntPtr.Zero,0,0,width+(outer.R-outer.L)-(client.R-client.L),height+(outer.B-outer.T)-(client.B-client.T),0x16))throw new Exception("Resize failed");
   return width+"x"+height;
  }
  [DllImport("user32.dll",EntryPoint="PostMessageW",CharSet=CharSet.Unicode,SetLastError=true)]
  static extern bool PostMessage(IntPtr h,uint message,IntPtr w,IntPtr l);
  public static void Text(IntPtr h,string text,int delay) {
   foreach(char c in text) {
    if(!PostMessage(h,0x102,(IntPtr)c,IntPtr.Zero))
     throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    if(delay>0) System.Threading.Thread.Sleep(delay);
   }
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

[Shot]::SetProcessDPIAware() | Out-Null
$entered=$false;$summary='failed'
try {
 Enter-Df3dLane -DfPath $dfPath -Port 5010;$entered=$true
 Get-FileHash "$dfPath/hack/plugins/df3d.plug.dll","$repo/tools/smoke/stockpile_search_native.lua",$PSCommandPath | ConvertTo-Json | Set-Content "$out/capture-inputs.json"
 Set-DfPrefs;Install-DfMenuStartup -DfPath $dfPath
 $owned=Start-Df3d -DfPath $dfPath
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'Source load failed'}
 $sizes=if($TruncationWidths){@(@(912,600,0),@(920,600,0),@(928,600,0),@(936,600,0),@(944,600,0),@(952,600,0))}else{@(@(1200,800,0),@(960,600,0),@(1920,1080,0),@(1920,1080,150))}
 if($TextMessages -or $HistoricalMaterials -or $TextChunks){$sizes=,@(1200,800,0)}
 foreach($size in $sizes) {
  $stageOut="$out/$($size[0])x$($size[1])-$($size[2])";New-Item -ItemType Directory -Path $stageOut | Out-Null
  $config=Invoke-DfhackRaw -CommandArgs @('lua',"local d=df.global.init.display;d.flag.INTERFACE_SCALING_TO_DESIRED_HEIGHT_WIDTH=$(([bool]($size[2] -eq 0)).ToString().ToLower());d.interface_scaling_percentage=$($size[2]);print('LAYOUT_CONFIGURED')")
  if($config.ExitCode -ne 0){throw ('Layout configuration failed: '+($config.Output -join ' '))}
  [Shot]::Resize([Shot]::Find($owned.Id),($size[0]+1),$size[1]) | Out-Null
  Start-Sleep -Milliseconds 300
  [Shot]::Resize([Shot]::Find($owned.Id),$size[0],$size[1]) | Set-Content "$stageOut/requested-size.txt"
  Start-Sleep -Milliseconds 1000
 $r=Invoke-DfhackRaw -CommandArgs @('lua',"df.global.d_init.feature.autosave=df.d_init_autosave.NONE;assert(loadfile([==[$repo/tools/smoke/stockpile_search_native.lua]==]))([==[$stageOut]==],$($TruncationWidths.ToString().ToLower()),$($HistoricalMaterials.ToString().ToLower()),$($TextChunks.ToString().ToLower()))")
 $r | ConvertTo-Json | Set-Content "$stageOut/native.log"
 if($r.ExitCode -ne 0 -or ($r.Output -join "`n") -notmatch 'STOCKPILE_SEARCH_STARTED'){throw 'Native capture start failed'}
 $limit=(Get-Date).AddSeconds(240)
 while(-not(Test-Path "$stageOut/result.json") -and (Get-Date) -lt $limit){Start-Sleep -Milliseconds 200}
 $result=Get-Content "$stageOut/result.json" -Raw | ConvertFrom-Json
 if(-not $result.success){throw $result.error}
  if($TextMessages) {
   $samples=@('abc XYZ',("a"+[char]0x00e9+[char]0x03b1+[char]0x4e2d+"b"),"ab`r`ncd`tef",('a'*80))
   $observations=@()
   foreach($text in $samples) {
    $prepare=Invoke-DfhackRaw -CommandArgs @('lua',"local c=df.global.game.main_interface.custom_stockpile;assert(c.open);c.entering_spec_filter=true;local gui=require('gui');local v=dfhack.gui.getDFViewscreen(true);for i=1,#c.spec_filter do gui.simulateInput(v,'STRING_A000')end;assert(c.spec_filter=='');assert(df.global.pause_state);print('TEXT_READY')")
    if($prepare.ExitCode -ne 0 -or ($prepare.Output -join "`n") -notmatch 'TEXT_READY'){throw 'Text preparation failed'}
    [Shot]::Text([Shot]::Find($owned.Id),$text,40)
    Start-Sleep -Milliseconds 500
    $read=Invoke-DfhackRaw -CommandArgs @('lua',"local c=df.global.game.main_interface.custom_stockpile;assert(c.open and df.global.pause_state);print('TEXT_RESULT '..require('json').encode{stored=dfhack.df2utf(c.spec_filter),editing=c.entering_spec_filter})")
    if($read.ExitCode -ne 0){throw 'Text read failed'}
    $raw=$read.Output -join "`n"
    $raw | Add-Content "$stageOut/text-messages.log"
    $start=$raw.IndexOf('TEXT_RESULT ')
    if($start -lt 0){throw 'Missing text observation'}
    $observations+=@{typed=$text;message_interval_ms=40;native=($raw.Substring($start+12) | ConvertFrom-Json)}
   }
   $observations | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 "$stageOut/text-messages.json"
  }
  [Shot]::Capture([Shot]::Find($owned.Id),"$stageOut/native.png") | Set-Content "$stageOut/actual-size.txt"
 }
 $summary='passed'
} catch {$summary='failed '+$_.Exception.Message}
finally {
 try {if($entered){Exit-Df3dLane}} catch {$summary='failed teardown '+$_.Exception.Message}
 try {if((Manifest) -cne $expected){throw 'Source changed'};'Owned source unchanged' | Set-Content "$out/save-preservation.txt"} catch {$summary='failed preservation '+$_.Exception.Message}
 $summary | Set-Content "$out/summary.txt";Write-Output "$summary -- $out"
}
if($summary -ne 'passed'){exit 1}




