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
    return (Get-Process -Id $p)
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
    param([string[]]$CommandArgs, [int]$TimeoutSec = 0)
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
    param([string[]]$CommandArgs, [int]$Retries = 3, [switch]$Quiet)
    $code = 1
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        $r = Invoke-DfhackRaw $CommandArgs
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
    $client = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "build\tools\session_client.exe"
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
    param([System.Diagnostics.Process]$Proc, [int]$UnknownTimeoutSec = 120)
    $started = Get-Date
    $unknownDeadline = $started.AddSeconds($UnknownTimeoutSec)
    $announced = $false
    $lastNag = $started
    while ($true) {
        try { $Proc.Refresh() } catch {}
        if ($Proc.HasExited) { return }
        $phase = Get-DfSavePhase
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
    param([int]$GracefulTimeoutMs = 30000, [switch]$Orderly)
    $proc = $script:DfProc
    if (-not $proc) { return }
    $script:DfProc = $null
    try { $proc.Refresh() } catch {}
    if ($proc.HasExited) { return }
    Wait-DfSaveIdle -Proc $proc
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
    Invoke-Dfhack @("die") -Retries 1 -Quiet | Out-Null
    if ($proc.WaitForExit(10000)) { return }
    Write-Host "[lane] terminating DF pid $($proc.Id)"
    Stop-Process -Id $proc.Id -Force -Confirm:$false -ErrorAction SilentlyContinue
}

Export-ModuleMember -Function Enter-Df3dLane, Exit-Df3dLane, Set-DfPrefs, Restore-DfPrefs, Install-DfSmokeScript, Install-DfMenuStartup, Start-Df3d, Start-ContainedProcess, Invoke-Dfhack, Invoke-DfhackRaw, Wait-DfFort, Stop-Df3d
