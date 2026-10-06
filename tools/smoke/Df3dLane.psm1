# Df3dLane: shared containment for the live lanes. Import with:
#   Import-Module (Join-Path $PSScriptRoot "Df3dLane.psm1") -Force
# Launched processes live in a kill-on-close job object with their own process
# group; a named mutex (Local\df3d_lane) enforces single occupancy; lanes stop
# only the DF they launched, by PID, never mid-save; prefs staging restores the
# original from backup unless the user edited prefs since.
# ASCII only: PowerShell 5.1 reads files without a BOM as ANSI.

Set-StrictMode -Version 2

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.ComponentModel;
public static class Df3dLaneNative {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern IntPtr CreateDesktop(string desktop, IntPtr device, IntPtr devmode, int flags, uint access, IntPtr sa);
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

    const uint GENERIC_ALL = 0x10000000;
    const uint CREATE_SUSPENDED = 0x4;
    const uint CREATE_NEW_PROCESS_GROUP = 0x200;
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;
    const int JobObjectExtendedLimitInformation = 9;

    // One job per lane process. Deliberately never closed: the handle's
    // lifetime IS the containment. When this process ends, the kernel
    // closes it and terminates every process still in the job.
    static IntPtr job = IntPtr.Zero;

    static Exception Fail(string call) {
        int err = Marshal.GetLastWin32Error();
        return new Win32Exception(err, call + " failed: " + new Win32Exception(err).Message + " (error " + err + ")");
    }

    static void EnsureJob() {
        if (job != IntPtr.Zero) return;
        IntPtr j = CreateJobObject(IntPtr.Zero, null);
        if (j == IntPtr.Zero) throw Fail("CreateJobObject");
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.Basic.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        int len = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
        IntPtr p = Marshal.AllocHGlobal(len);
        try {
            Marshal.StructureToPtr(info, p, false);
            if (!SetInformationJobObject(j, JobObjectExtendedLimitInformation, p, (uint)len)) throw Fail("SetInformationJobObject");
        } finally { Marshal.FreeHGlobal(p); }
        job = j;
    }

    // Launch exe (with args) in cwd, on the named desktop (null = the
    // caller's desktop), contained in this process's job object. The
    // process starts suspended, is assigned to the job, then resumed, so
    // there is no window in which it runs uncontained.
    public static int Launch(string exePath, string args, string workingDir, string desktopName) {
        EnsureJob();
        // PowerShell marshals $null to "" for string parameters; both mean
        // "the caller's desktop".
        if (String.IsNullOrEmpty(desktopName)) desktopName = null;
        if (desktopName != null) {
            IntPtr desk = CreateDesktop(desktopName, IntPtr.Zero, IntPtr.Zero, 0, GENERIC_ALL, IntPtr.Zero);
            if (desk == IntPtr.Zero) throw Fail("CreateDesktop");
        }
        STARTUPINFO si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
        si.lpDesktop = desktopName;
        PROCESS_INFORMATION pi;
        string cmd = "\"" + exePath + "\"" + (String.IsNullOrEmpty(args) ? "" : " " + args);
        uint flags = CREATE_SUSPENDED | CREATE_NEW_PROCESS_GROUP;
        if (!CreateProcess(exePath, cmd, IntPtr.Zero, IntPtr.Zero, false, flags, IntPtr.Zero, workingDir, ref si, out pi))
            throw Fail("CreateProcess");
        if (!AssignProcessToJobObject(job, pi.hProcess)) {
            int err = Marshal.GetLastWin32Error();
            TerminateProcess(pi.hProcess, 1);
            CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
            throw new Win32Exception(err, "AssignProcessToJobObject failed; refusing to run DF uncontained");
        }
        ResumeThread(pi.hThread);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
        return pi.dwProcessId;
    }
}
"@

$script:LaneMutex = $null
$script:DfPath = $null
$script:PrefsFile = $null
$script:PrefsBackup = $null
$script:DfhackRun = $null
$script:Port = 5010
$script:DfProc = $null
$script:StagedFiles = @()
$script:AttachOnly = $false
$script:DfVisible = $false

function Enter-Df3dLane {
    <#
    .SYNOPSIS
    Acquire the single-lane mutex and refuse to proceed if another DF
    instance is already running. Call once at the top of a lane.
    #>
    param([string]$DfPath, [int]$Port = 5010, [switch]$AttachOnly)
    $script:AttachOnly = [bool]$AttachOnly
    $script:DfPath = $DfPath
    $script:DfhackRun = Join-Path $DfPath "hack\dfhack-run.exe"
    $script:PrefsFile = Join-Path $DfPath "prefs\init.txt"
    $script:Port = $Port

    $created = $false
    $m = New-Object System.Threading.Mutex($false, "Local\df3d_lane", [ref]$created)
    if (-not $m.WaitOne(0)) {
        throw "another DF3D session (Play.cmd or a smoke script) is already running; close it first."
    }
    $script:LaneMutex = $m

    $existing = @(Get-Process -Name "Dwarf Fortress" -ErrorAction SilentlyContinue)
    if ($existing.Count -gt 0 -and -not $AttachOnly) {
        $m.ReleaseMutex(); $script:LaneMutex = $null
        $pids = ($existing | ForEach-Object { $_.Id }) -join ', '
        throw "Dwarf Fortress is already running (pid $pids). DF3D never stops a Dwarf Fortress it did not start; close it (or let its session finish) and retry."
    }
}

function Exit-Df3dLane {
    <#
    .SYNOPSIS
    Idempotent teardown: stop our DF (wait out any save -> die -> terminate
    by PID), restore prefs, remove staged files, release the mutex. Prefs
    and staged files are restored even if stopping DF throws.
    #>
    try {
        Stop-Df3d
    } finally {
        Restore-DfPrefs
        foreach ($f in $script:StagedFiles) {
            if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
        }
        $script:StagedFiles = @()
        if ($script:LaneMutex) {
            try { $script:LaneMutex.ReleaseMutex() } catch {}
            $script:LaneMutex = $null
        }
    }
}

function ConvertTo-DfLanePrefs {
    <#
    .SYNOPSIS
    The staging transform Set-DfPrefs applies to prefs/init.txt lines:
    silent + windowed, plus classic ASCII when requested. Also used to
    recognise a file an interrupted run staged and the user never touched.
    #>
    param([string[]]$Lines, [switch]$ClassicAscii)
    # SOUND:NO alone does not silence DF v50's FMOD audio; zero every
    # volume channel as well.
    $out = @($Lines) -replace '\[SOUND:YES\]', '[SOUND:NO]' -replace '\[WINDOWED:NO\]', '[WINDOWED:YES]' `
        -replace '\[MASTER_VOLUME:\d+\]', '[MASTER_VOLUME:0]' `
        -replace '\[MUSIC_VOLUME:\d+\]', '[MUSIC_VOLUME:0]' `
        -replace '\[AMBIENCE_VOLUME:\d+\]', '[AMBIENCE_VOLUME:0]' `
        -replace '\[SFX_VOLUME:\d+\]', '[SFX_VOLUME:0]'
    if ($ClassicAscii) { $out = $out -replace '\[USE_CLASSIC_ASCII:NO\]', '[USE_CLASSIC_ASCII:YES]' }
    return ,@($out)
}

function Set-DfPrefs {
    <#
    .SYNOPSIS
    Back up prefs/init.txt and rewrite it silent + windowed. Windowed
    matters as much as silence: a fullscreen DF covers the terminal hosting
    the lane and looks exactly like the terminal vanished. -ClassicAscii
    also stages [USE_CLASSIC_ASCII:YES] (the classic glyph probe reads the
    character cells DF draws in that mode); the same backup restores it.
    #>
    param([switch]$ClassicAscii)
    if ($script:AttachOnly) { throw "Attach lanes cannot stage DF preferences" }
    $backup = "$($script:PrefsFile).df3d-backup"
    if (Test-Path $backup) {
        # A backup left by an interrupted run is the original ONLY if the
        # current file is still exactly what that run staged from it. The
        # interrupted run may have staged with either -ClassicAscii setting,
        # so accept both. Anything else means the user played DF and changed
        # settings since; those must not be replaced by the stale backup.
        $current = @(Get-Content $script:PrefsFile) -join "`n"
        $original = @(Get-Content $backup)
        $untouched = $false
        foreach ($ascii in @($false, $true)) {
            if ($current -eq ((ConvertTo-DfLanePrefs -Lines $original -ClassicAscii:$ascii) -join "`n")) { $untouched = $true }
        }
        if ($untouched) {
            Write-Host "[lane] WARNING: prefs backup from an interrupted run found; restoring it before staging" -ForegroundColor Yellow
            Copy-Item $backup $script:PrefsFile -Force
        } else {
            $aside = "$backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            Move-Item $backup $aside -Force
            Write-Host "[lane] WARNING: prefs backup from an interrupted run found, but prefs/init.txt was edited since; keeping the current file and moving the old backup aside for reference: $aside" -ForegroundColor Yellow
        }
    }
    Copy-Item $script:PrefsFile $backup -Force
    $script:PrefsBackup = $backup
    $prefs = ConvertTo-DfLanePrefs -Lines @(Get-Content $script:PrefsFile) -ClassicAscii:$ClassicAscii
    Set-Content $script:PrefsFile $prefs -Encoding ascii
}

function Restore-DfPrefs {
    if ($script:PrefsBackup -and (Test-Path $script:PrefsBackup)) {
        Copy-Item $script:PrefsBackup $script:PrefsFile -Force
        Remove-Item $script:PrefsBackup -Force
    }
    $script:PrefsBackup = $null
    Remove-DfMenuStartup
}

function Remove-DfMenuStartup {
    # Drop the enable-only startup file (ours from this run, or one left by
    # an interrupted run). Only the exact payload is removed; customized
    # content is left alone, matching Install-DfMenuStartup.
    if ($script:AttachOnly -or -not $script:DfPath) { return }
    $initFile = Join-Path $script:DfPath "dfhack-config\init\dfhackzzz_df3d_menu.init"
    if (-not (Test-Path -LiteralPath $initFile)) { return }
    $content = Get-Content -LiteralPath $initFile -Raw
    if ($content -and $content.Trim() -eq 'enable df3d') { Remove-Item -LiteralPath $initFile -Force -ErrorAction SilentlyContinue }
}

function Install-DfSmokeScript {
    <#
    .SYNOPSIS
    Stage df3d-smoke.lua and the init file that runs it; both are removed
    by Exit-Df3dLane.
    #>
    param([string]$DfPath, [string]$SourceDir)
    if ($script:AttachOnly) { throw "Attach lanes cannot stage DF scripts" }
    $initDir = Join-Path $DfPath "dfhack-config\init"
    $initFile = Join-Path $initDir "dfhackzzz_df3d_smoke.init"
    $dst = Join-Path $DfPath "hack\scripts\df3d-smoke.lua"
    Copy-Item (Join-Path $SourceDir "df3d-smoke.lua") $dst -Force
    New-Item -ItemType Directory -Force $initDir | Out-Null
    Set-Content $initFile "enable df3d`ndf3d-smoke" -Encoding ascii
    $script:StagedFiles += @($initFile, $dst)
}

function Install-DfMenuStartup {
    # Interactive startup enables the bridge without selecting or loading a save.
    param([string]$DfPath)
    if ($script:AttachOnly) { throw "Attach lanes cannot stage DF scripts" }
    $initDir = Join-Path $DfPath "dfhack-config\init"
    $initFile = Join-Path $initDir "dfhackzzz_df3d_menu.init"
    # A force-closed launcher can leave its enable-only file behind. Reclaim
    # that exact payload, but preserve any unexpected/customized content.
    if ((Test-Path -LiteralPath $initFile) -and (Get-Content -LiteralPath $initFile -Raw).Trim() -ne 'enable df3d') {
        throw "Existing menu startup file has unexpected content: $initFile"
    }
    New-Item -ItemType Directory -Force $initDir | Out-Null
    Set-Content -LiteralPath $initFile 'enable df3d' -Encoding ascii
    $script:StagedFiles += $initFile
}

function Start-Df3d {
    <#
    .SYNOPSIS
    Launch Dwarf Fortress contained. Hidden desktop by default; -Visible
    launches on the caller's desktop (still windowed, still contained).
    Returns the Process object.
    #>
    param([string]$DfPath, [switch]$Visible)
    if ($script:AttachOnly) { throw "Attach lanes cannot launch or own DF" }
    $script:DfVisible = [bool]$Visible
    $exe = Join-Path $DfPath "Dwarf Fortress.exe"
    $env:DFHACK_DISABLE_CONSOLE = "1"
    $env:DFHACK_PORT = "$($script:Port)"
    $desktop = if ($Visible) { $null } else { "df3d_hidden" }
    if ($Visible) { Write-Host "[lane] launching Dwarf Fortress (visible, windowed; do not interact)" }
    else { Write-Host "[lane] launching Dwarf Fortress on hidden desktop 'df3d_hidden'" }
    $dfPid = [Df3dLaneNative]::Launch($exe, "", $DfPath, $desktop)
    $script:DfProc = Get-Process -Id $dfPid
    Write-Host "[lane] DF pid $dfPid (job-contained: dies with this lane)"
    return $script:DfProc
}

function Start-ContainedProcess {
    <#
    .SYNOPSIS
    Launch any other exe (e.g. Godot) in the lane's job object.
    The parameter is named -Arguments, not -Args: a parameter called
    $Args collides with PowerShell's automatic $args variable and is
    always empty, which silently launched Godot with no arguments at all
    (it only worked because the working directory was the project).
    #>
    param([string]$Exe, [string]$Arguments = "", [string]$WorkingDir, [switch]$Visible)
    if ($Arguments -eq "") { Write-Host "[lane] note: launching $([System.IO.Path]::GetFileName($Exe)) with no arguments" }
    $desktop = if ($Visible) { $null } else { "df3d_hidden" }
    $p = [Df3dLaneNative]::Launch($Exe, $Arguments, $WorkingDir, $desktop)
    $process = Get-Process -Id $p
    # Get-Process alone can lose ExitCode after HasExited/Refresh on PowerShell
    # 5.1. Keep a handle while the child lives so terminal status stays readable.
    $null = $process.Handle
    return $process
}

function ConvertTo-Win32Argument([string]$a) {
    # Quote per CommandLineToArgvW rules so the child sees exactly $a.
    if ($a -notmatch '[\s"]' -and $a.Length -gt 0) { return $a }
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $a.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') { [void]$sb.Append('\' * ($bs * 2 + 1)); [void]$sb.Append('"'); $bs = 0; continue }
        if ($bs -gt 0) { [void]$sb.Append('\' * $bs); $bs = 0 }
        [void]$sb.Append($ch)
    }
    if ($bs -gt 0) { [void]$sb.Append('\' * ($bs * 2)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function Invoke-DfhackRaw {
    <#
    .SYNOPSIS
    Run dfhack-run.exe once in its OWN windowless console and return
    @{ ExitCode; Output } (stdout+stderr lines).

    Why not "& dfhack-run": on a successful connection dfhack-run calls
    DFHack's Console::init(), which ends with ShowWindow(GetConsoleWindow(),
    SW_HIDE). Started from a terminal, it inherits THAT console, so every
    successful call hides the terminal hosting the lane, which looks like
    a terminal crash. With
    CreateNoWindow the child gets a private console and hides only that.
    #>
    param([string[]]$CommandArgs, [int]$TimeoutSec = 30)
    # A 30 s default: a hung DFHack (DF inside a save, hidden console) must never
    # park the lane in WaitForExit forever. Callers that legitimately run long
    # Lua stages pass their own -TimeoutSec; 0 or less waits without limit.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $script:DfhackRun
    $psi.Arguments = ($CommandArgs | ForEach-Object { ConvertTo-Win32Argument $_ }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.RedirectStandardInput = $true
    $psi.EnvironmentVariables["DFHACK_PORT"] = "$($script:Port)"
    $p = [System.Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEndAsync()
    $err = $p.StandardError.ReadToEndAsync()
    if ($TimeoutSec -le 0) { $p.WaitForExit() }
    elseif (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $p.Kill(); $p.WaitForExit()
        return @{ ExitCode = 124; Output = @("DFHack request timed out after $TimeoutSec seconds") }
    }
    $lines = @()
    foreach ($s in @($out.Result, $err.Result)) {
        if ($s) { $lines += ($s -split "`r?`n" | Where-Object { $_ -ne '' }) }
    }
    return @{ ExitCode = $p.ExitCode; Output = $lines }
}

function Invoke-Dfhack {
    <#
    .SYNOPSIS
    Run a dfhack-run command; returns the exit code only (output goes to
    the host). Retries: dfhack-run.exe intermittently AVs in MSVCP140 at
    exit (WER-confirmed), surfacing as "I/O error in
    receive header" and a bogus nonzero exit even though the server is
    healthy.
    #>
    param([string[]]$CommandArgs, [int]$Retries = 3, [switch]$Quiet, [int]$TimeoutSec = 30)
    $code = 1
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $r = Invoke-DfhackRaw $CommandArgs -TimeoutSec $TimeoutSec
        $code = $r.ExitCode
        if (-not $Quiet) { $r.Output | ForEach-Object { Write-Host "    $_" } }
        if ($code -eq 0) { return 0 }
        if ($attempt -lt $Retries) {
            if (-not $Quiet) { Write-Host "    (attempt $attempt failed with exit $code)" }
            Start-Sleep -Seconds 2
        }
    }
    return $code
}

function Wait-DfFort {
    <#
    .SYNOPSIS
    Poll until the fort is loaded. Returns 'ready' | 'exited' | 'timeout'.
    #>
    param([int]$TimeoutSec = 420)
    $proc = $script:DfProc
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        if ($proc.HasExited) { return 'exited' }
        $r = Invoke-DfhackRaw @("lua", "print(dfhack.gui.matchFocusString('dwarfmode/Default'))")
        if ($r.ExitCode -eq 0 -and ($r.Output -join ' ') -match 'true') { return 'ready' }
    }
    return 'timeout'
}

function Get-DfSavePhase {
    <#
    .SYNOPSIS
    Report whether the bridge says DF is saving. Returns 'saving', 'idle'
    or 'unknown' (nothing could be read).

    The session phase lives in the bridge's session shm (SessionPhase;
    Saving = 6 in schema/mirror.fbs) and is read with
    build/tools/session_client.exe status, which never goes through
    DFHack: a dfhack-run command can block for the whole save because DF's
    main thread is inside the save routine. The phase is published BEFORE
    the save starts, so the shm reading stays valid throughout. session_client
    loops for up to five minutes when no session channel exists, so it is
    run with a hard timeout. Without it (not built, or no session channel),
    "df3d status" through dfhack-run is the fallback: a healthy answer is
    treated as idle, exactly what teardown assumed before this check.
    #>
    param([string]$SessionClient = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\tools\session_client.exe'))
    $client = $SessionClient
    if (Test-Path -LiteralPath $client) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $client
            $psi.Arguments = "status"
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $out = $p.StandardOutput.ReadToEndAsync()
            $err = $p.StandardError.ReadToEndAsync()
            if (-not $p.WaitForExit(5000)) { try { $p.Kill(); $p.WaitForExit() } catch {} }
            elseif ($p.ExitCode -eq 0 -and $out.Result -match 'SESSION phase=(\d+)') {
                if ([int]$Matches[1] -eq 6) { return 'saving' }
                return 'idle'
            }
            [void]$err.Result
        } catch {}
    }
    try {
        $r = Invoke-DfhackRaw @("df3d", "status") -TimeoutSec 10
        if ($r.ExitCode -eq 0 -and ($r.Output -join "`n") -match 'mirroring enabled:') { return 'idle' }
    } catch {}
    return 'unknown'
}

function Wait-DfSaveIdle {
    <#
    .SYNOPSIS
    Block while DF is saving. Polls every 2 s. 'unknown' readings are
    tolerated for -UnknownTimeoutSec, after which the caller falls through
    to the pre-existing shutdown. A confirmed save is NEVER abandoned: the
    lane's job object (KILL_ON_JOB_CLOSE, handle held for the lane's
    lifetime) terminates DF the moment this console closes, so "leave DF
    running" is not an option; the only safe move is to keep waiting and
    keep saying so.
    #>
    param([System.Diagnostics.Process]$Proc, [int]$UnknownTimeoutSec = 120,
        [string]$SessionClient = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\tools\session_client.exe'))
    $started = Get-Date
    $unknownDeadline = $started.AddSeconds($UnknownTimeoutSec)
    $announced = $false
    $lastNag = $started
    while ($true) {
        try { $Proc.Refresh() } catch {}
        if ($Proc.HasExited) { return }
        $phase = Get-DfSavePhase -SessionClient $SessionClient
        if ($phase -eq 'idle') { return }
        $now = Get-Date
        if ($phase -eq 'saving') {
            $unknownDeadline = $now.AddSeconds($UnknownTimeoutSec)
            if (-not $announced) {
                Write-Host "[lane] DF is saving; waiting before shutdown" -ForegroundColor Yellow
                $announced = $true; $lastNag = $now
            } elseif (($now - $lastNag).TotalSeconds -ge 10) {
                $elapsed = [int]($now - $started).TotalSeconds
                Write-Host "[lane] DF is still saving after $elapsed s; the lane keeps waiting. Do NOT close this window: DF (pid $($Proc.Id), hidden desktop 'df3d_hidden') is job-contained and would be killed mid-save." -ForegroundColor Yellow
                $lastNag = $now
            }
        } elseif ($now -ge $unknownDeadline) {
            Write-Host "[lane] could not read DF's save state for $UnknownTimeoutSec s (DFHack unresponsive); proceeding with shutdown" -ForegroundColor Yellow
            return
        }
        Start-Sleep -Seconds 2
    }
}

function Stop-Df3d {
    <#
    .SYNOPSIS
    Stop the DF instance THIS lane launched, by PID only. Never by name.
    Waits first while the bridge reports DF saving (Wait-DfSaveIdle).

    Default is "dfhack die" (TerminateProcess from inside DF): DF 53.x
    under DFHack double-frees in its own atexit handlers on every orderly
    quit - reproduced with df3d.plug.dll removed - which costs a
    WER dump (~53 MB) and an Application Error event per run. Lanes never
    save, so skipping DF's shutdown loses nothing. -Orderly uses DF's own
    QUIT path (exercises plugin_shutdown; expect the crash at the end).
    #>
    param([int]$GracefulTimeoutMs = 30000, [switch]$Orderly,
        [string]$SessionClient = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\tools\session_client.exe'))
    $proc = $script:DfProc
    if (-not $proc) { return }
    $script:DfProc = $null
    try { $proc.Refresh() } catch {}
    if ($proc.HasExited) { return }
    Wait-DfSaveIdle -Proc $proc -SessionClient $SessionClient
    try { $proc.Refresh() } catch {}
    if ($proc.HasExited) { return }
    if ($Orderly) {
        Write-Host "[lane] quitting DF orderly (pid $($proc.Id))"
        Invoke-Dfhack @("lua", "dfhack.gui.getCurViewscreen().breakdown_level=df.interface_breakdown_types.QUIT") -Retries 1 -Quiet | Out-Null
        if ($proc.WaitForExit($GracefulTimeoutMs)) { return }
        Write-Host "[lane] orderly quit timed out; dfhack die"
    } else {
        Write-Host "[lane] stopping DF (pid $($proc.Id)) via dfhack die"
    }
    Invoke-Dfhack @("die") -Retries 1 -Quiet -TimeoutSec ([Math]::Max(1, [Math]::Ceiling($GracefulTimeoutMs / 1000))) | Out-Null
    if ($proc.WaitForExit(10000)) { return }
    Write-Host "[lane] terminating DF pid $($proc.Id)"
    Stop-Process -Id $proc.Id -Force -Confirm:$false -ErrorAction SilentlyContinue
}

function ConvertFrom-Df3dSessionStatus {
    param([string]$Text)
    # Epoch must be last: messages, names and save paths can contain spaces.
    $pattern = '(?m)^SESSION phase=(\d+) seq=\d+ result=\d+ paused=([01]) year=-?\d+ year_tick=-?\d+ fort=.*? id=(.*?) message=(.*?) epoch=(\d+)\r?$'
    if ($Text -notmatch $pattern) { return $null }
    $epoch = [uint64]0
    if (-not [uint64]::TryParse($Matches[5], [ref]$epoch)) { return $null }
    return @{ Phase=[int]$Matches[1]; Paused=($Matches[2] -eq '1'); SaveId=$Matches[3]; Message=$Matches[4]; Epoch=$epoch }
}

function Test-Df3dReloadIdentity {
    param($State, [string]$SaveId, [int]$ProcessId)
    return ($null -ne $State -and $State.Phase -eq 3 -and $State.Paused -and
        $State.SaveId -ceq $SaveId -and $State.Epoch -ne 0 -and
        ([uint64]$State.Epoch -shr 32) -eq [uint64]$ProcessId)
}

function Invoke-DfSessionClient {
    param([string]$SessionClient, [string[]]$Arguments, [int]$TimeoutMs, [System.Diagnostics.Process]$Owner)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $SessionClient
    $psi.Arguments = ($Arguments | ForEach-Object { ConvertTo-Win32Argument $_ }) -join ' '
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    try {
        $stdout = $p.StandardOutput.ReadToEndAsync(); $stderr = $p.StandardError.ReadToEndAsync()
        $timer = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.WaitForExit([Math]::Min(100, [Math]::Max(1, $TimeoutMs - [int]$timer.ElapsedMilliseconds)))) {
            if ($Owner) { $Owner.Refresh() }
            if (($Owner -and $Owner.HasExited) -or $timer.ElapsedMilliseconds -ge $TimeoutMs) {
                $p.Kill(); $p.WaitForExit()
                return @{ ExitCode=124; Output=$stdout.Result; Error=$stderr.Result; OwnerExited=($Owner -and $Owner.HasExited) }
            }
        }
        return @{ ExitCode=$p.ExitCode; Output=$stdout.Result; Error=$stderr.Result; OwnerExited=$false }
    } finally {
        if (-not $p.HasExited) { $p.Kill(); $p.WaitForExit() }
        $p.Dispose()
    }
}

function Restart-Df3dFortress {
    <# Restart only the owned process, preserving the lane mutex and staging.
    No save command is sent. Bound excluding hashing and an honored in-progress
    save: status 5s + stop 15s/unknown phase 120s + load TimeoutSec + verify 30s
    + 10s overhead = TimeoutSec + 180s. Hashing is included in ElapsedSec.
    A timeout kills the client child only; teardown still owns the DF process.
    Route inprocess uses semantic Quit once and verifies Menu/epoch0 before load,
    retaining the owned process and DLL. Its bound excluding hashing is
    2 * TimeoutSec + 40s (unload, load, status verification); no restart fallback.
    #>
    param([Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$SaveId,
        [ValidateSet('restart','inprocess')][string]$Route = 'restart',
        [ValidateRange(1,7200)][int]$TimeoutSec = 420,
        [string]$SessionClient = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\tools\session_client.exe'),
        [string[]]$SaveRoots = @(), [Parameter(Mandatory)][string]$EvidenceDir)
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $result = @{ Status='failed'; Reason='Restart did not complete'; Route=$Route; PreviousPid=0; Pid=0;
        PreviousEpoch=[uint64]0; Epoch=[uint64]0; SaveId=$SaveId; ElapsedSec=0.0 }
    $manifest = $null
    try {
        if ($script:AttachOnly -or -not $script:DfProc -or -not $script:LaneMutex) {
            $result.Reason='Restart requires an owned process and held lane mutex'; return $result
        }
        $proc = $script:DfProc; $proc.Refresh(); $result.PreviousPid=$proc.Id
        if ($proc.HasExited) { $result.Reason='Owned process already exited'; return $result }
        $menu = Join-Path $script:DfPath 'dfhack-config\init\dfhackzzz_df3d_menu.init'
        $smoke = Join-Path $script:DfPath 'dfhack-config\init\dfhackzzz_df3d_smoke.init'
        if ($script:StagedFiles.Count -ne 1 -or $script:StagedFiles[0] -ne $menu -or
            -not (Test-Path -LiteralPath $menu) -or (Get-Content -LiteralPath $menu -Raw).Trim() -ne 'enable df3d' -or
            (Test-Path -LiteralPath $smoke)) {
            $result.Status='incomplete'; $result.Reason='Restart requires only the enable-only menu startup file'; return $result
        }
        $before = Invoke-DfSessionClient -SessionClient $SessionClient -Arguments @('status') -TimeoutMs 5000 -Owner $proc
        $state = ConvertFrom-Df3dSessionStatus $before.Output
        if ($before.ExitCode -ne 0 -or -not $state) {
            $result.Status='incomplete'; $result.Reason="Pre-restart status unavailable (exit $($before.ExitCode))"; return $result
        }
        $result.PreviousEpoch=$state.Epoch
        if ($state.Phase -eq 6) { $result.Reason='DF is saving; restart refused'; return $result }
        if ($state.Phase -ne 3 -or $state.SaveId -cne $SaveId -or
            ([uint64]$state.Epoch -shr 32) -ne [uint64]$proc.Id) {
            $result.Reason='Pre-restart fortress identity does not match the owned process'; return $result
        }
        New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
        if (-not $SaveRoots.Count) {
            $SaveRoots=@((Join-Path $script:DfPath 'save'), (Join-Path $env:APPDATA 'Bay 12 Games/Dwarf Fortress/save'))
        }
        $roots=@($SaveRoots | ForEach-Object { [IO.Path]::GetFullPath($_).TrimEnd('\','/') })
        Write-Host '[lane] hashing save roots before restart'
        $files=[System.Collections.Generic.List[object]]::new()
        for ($i=0; $i -lt $roots.Count; $i++) {
            if (-not (Test-Path -LiteralPath $roots[$i])) { continue }
            foreach ($file in Get-ChildItem -LiteralPath $roots[$i] -Recurse -File) {
                $files.Add([pscustomobject]@{Root=$i; Path=$file.FullName.Substring($roots[$i].Length).TrimStart('\','/');
                    Hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash})
            }
        }
        $manifest=[pscustomobject]@{Roots=$roots; Backup=$EvidenceDir; AllowedDirectories=@('current'); Files=$files.ToArray()}
        Write-Host "[lane] recorded $($files.Count) save-file hashes"
        $manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $EvidenceDir 'manifest.json') -Encoding UTF8
        if ($Route -eq 'inprocess') {
            # One semantic submission. An uncertain unload must never cause a
            # replay, process restart, or load into an unverified native state.
            $quit = Invoke-DfSessionClient -SessionClient $SessionClient -Arguments @('quit-without-saving') -TimeoutMs ($TimeoutSec*1000) -Owner $proc
            $quit | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDir 'quit.json') -Encoding UTF8
            $proc.Refresh()
            if ($quit.ExitCode -ne 0 -or $proc.HasExited) {
                $result.Status='incomplete'; $result.Reason="Native unload unverified (exit $($quit.ExitCode), process exited=$($proc.HasExited)); no retry"; return $result
            }
            $title = Invoke-DfSessionClient -SessionClient $SessionClient -Arguments @('status') -TimeoutMs 5000 -Owner $proc
            $title | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDir 'title.json') -Encoding UTF8
            $titleState = ConvertFrom-Df3dSessionStatus $title.Output
            if ($title.ExitCode -ne 0 -or -not $titleState -or $titleState.Phase -ne 1 -or $titleState.Epoch -ne 0) {
                $result.Reason='Native unload did not establish Menu with epoch zero'; return $result
            }
            $next=$proc
        } else {
        $visible=$script:DfVisible
        Stop-Df3d -SessionClient $SessionClient -GracefulTimeoutMs 5000
        $proc.Refresh()
        if (-not $proc.HasExited) { $result.Reason='Owned process did not exit'; return $result }
        if (@(Get-Process -Name 'Dwarf Fortress' -ErrorAction SilentlyContinue).Count) {
            $result.Status='incomplete'; $result.Reason='Foreign DF appeared after stop; left running'; return $result
        }
        try { $next = Start-Df3d -DfPath $script:DfPath -Visible:$visible }
        catch { $result.Status='incomplete'; $result.Reason='Restart launch failed: '+$_.Exception.Message; return $result }
        }
        $result.Pid=$next.Id
        $loaded = Invoke-DfSessionClient -SessionClient $SessionClient -Arguments @('load',$SaveId) -TimeoutMs ($TimeoutSec*1000) -Owner $next
        $loaded | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDir 'load.json') -Encoding UTF8
        $next.Refresh()
        if ($loaded.ExitCode -ne 0 -or $next.HasExited) {
            $result.Status='incomplete'; $result.Reason="Restart load failed (exit $($loaded.ExitCode), process exited=$($next.HasExited))"; return $result
        }
        $verify = [Diagnostics.Stopwatch]::StartNew()
        while ($verify.ElapsedMilliseconds -lt 30000) {
            $reply = Invoke-DfSessionClient -SessionClient $SessionClient -Arguments @('status') -TimeoutMs ([Math]::Min(5000,30000-[int]$verify.ElapsedMilliseconds)) -Owner $next
            $state = ConvertFrom-Df3dSessionStatus $reply.Output
            if ($reply.ExitCode -eq 0 -and (Test-Df3dReloadIdentity $state $SaveId $next.Id) -and
                $state.Epoch -ne $result.PreviousEpoch) {
                $result.Epoch=$state.Epoch; $result.Status='ready'; $result.Reason=''; break
            }
            if ($reply.OwnerExited) { $result.Status='incomplete'; $result.Reason='Restarted DF exited during status verification'; return $result }
            # A ready reply with the wrong identity is conclusive; do not wait it out.
            if ($state -and $state.Phase -eq 3) { break }
            Start-Sleep -Milliseconds 100
        }
        if ($result.Status -ne 'ready') { $result.Reason='Restart identity verification failed (phase, pause, save id or epoch)' }
        return $result
    } catch {
        $result.Status='failed'; $result.Reason=$_.Exception.Message; return $result
    } finally {
        if ($manifest) {
            try {
                # Missing roots are equivalent to empty roots until DF creates them.
                foreach ($root in $manifest.Roots) { if (-not (Test-Path -LiteralPath $root)) { New-Item -ItemType Directory -Path $root | Out-Null } }
                # Force-reloading here removes the caller's exported hash command.
                # Reuse the loaded module so its outer-lane verification survives.
                Import-Module (Join-Path $PSScriptRoot 'SaveIsolation.psm1')
                Write-Host '[lane] verifying save hashes after restart'
                Assert-DfSaveBackupUnchanged -Manifest $manifest | Out-Null
            } catch { $result.Status='failed'; $result.Reason='Save integrity check failed: '+$_.Exception.Message }
        }
        $result.ElapsedSec=$timer.Elapsed.TotalSeconds
        if (Test-Path -LiteralPath $EvidenceDir) {
            $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $EvidenceDir 'restart.json') -Encoding UTF8
        }
    }
}

Export-ModuleMember -Function Enter-Df3dLane, Exit-Df3dLane, Set-DfPrefs, Restore-DfPrefs, Install-DfSmokeScript, Install-DfMenuStartup, Start-Df3d, Start-ContainedProcess, Invoke-Dfhack, Invoke-DfhackRaw, Wait-DfFort, Stop-Df3d, Restart-Df3dFortress, ConvertFrom-Df3dSessionStatus, Test-Df3dReloadIdentity
