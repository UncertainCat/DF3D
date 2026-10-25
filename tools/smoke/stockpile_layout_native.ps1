param([string]$CloneEvidence="build/native-save-effects-20260930-081415")
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
$out="$repo/build/stockpile-layout-native-$(Get-Date -Format yyyyMMdd-HHmmss)"
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
 Get-FileHash "$dfPath/hack/plugins/df3d.plug.dll","$repo/tools/smoke/stockpile_layout_native.lua",$PSCommandPath | ConvertTo-Json | Set-Content "$out/capture-inputs.json"
 Set-DfPrefs;Install-DfMenuStartup -DfPath $dfPath
 $owned=Start-Df3d -DfPath $dfPath
 & "$repo/build/tools/session_client.exe" load $clone *> "$out/load.log"
 if($LASTEXITCODE -ne 0){throw 'Source load failed'}
 foreach($size in @(@(1200,800,0),@(960,600,0),@(800,600,0),@(1920,1080,0),@(1200,800,150),@(1920,1080,150))) {
  $stageOut="$out/$($size[0])x$($size[1])-$($size[2])";New-Item -ItemType Directory -Path $stageOut | Out-Null
  $config=Invoke-DfhackRaw -CommandArgs @('lua',"local d=df.global.init.display;d.flag.INTERFACE_SCALING_TO_DESIRED_HEIGHT_WIDTH=$(([bool]($size[2] -eq 0)).ToString().ToLower());d.interface_scaling_percentage=$($size[2]);print('LAYOUT_CONFIGURED')")
  if($config.ExitCode -ne 0){throw 'Layout configuration failed'}
  [Shot]::Resize([Shot]::Find($owned.Id),($size[0]+1),$size[1]) | Out-Null
  Start-Sleep -Milliseconds 300
  [Shot]::Resize([Shot]::Find($owned.Id),$size[0],$size[1]) | Set-Content "$stageOut/requested-size.txt"
  Start-Sleep -Milliseconds 1000
 $r=Invoke-DfhackRaw -CommandArgs @('lua',"df.global.d_init.feature.autosave=df.d_init_autosave.NONE;assert(loadfile([==[$repo/tools/smoke/stockpile_layout_native.lua]==]))([==[$stageOut]==])")
 $r | ConvertTo-Json | Set-Content "$stageOut/native.log"
 if($r.ExitCode -ne 0 -or ($r.Output -join "`n") -notmatch 'STOCKPILE_LAYOUT_STARTED'){throw 'Native capture start failed'}
 $limit=(Get-Date).AddSeconds(240)
 while(-not(Test-Path "$stageOut/result.json") -and (Get-Date) -lt $limit){Start-Sleep -Milliseconds 200}
 $result=Get-Content "$stageOut/result.json" -Raw | ConvertFrom-Json
 if(-not $result.success){throw $result.error}
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



