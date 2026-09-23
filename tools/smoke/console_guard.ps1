# Console guard: dfhack-run.exe hides the console it inherits, so a terminal
# that launches it directly can vanish. This watches a console window, restores
# it within ~2 s of being hidden and logs the likely hiding caller.
# Usage: powershell -NoProfile -ExecutionPolicy Bypass -File tools\smoke\console_guard.ps1
# It relaunches itself detached (minimized); log: %TEMP%\df3d_console_guard.log
param(
    [int]$Hwnd = 0,
    [string]$Log = "",
    [int]$Hours = 12,
    [switch]$Worker
)
$ErrorActionPreference = 'Continue'
if ($Log -eq "") { $Log = Join-Path $env:TEMP "df3d_console_guard.log" }

Add-Type -Name Native -Namespace ConsoleGuard -MemberDefinition @'
[DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
'@

if (-not $Worker) {
    if ($Hwnd -eq 0) { $Hwnd = [int][ConsoleGuard.Native]::GetConsoleWindow() }
    if ($Hwnd -eq 0) { Write-Host "[guard] no console window to protect"; exit 1 }
    $self = $MyInvocation.MyCommand.Path
    Start-Process -FilePath powershell -WindowStyle Minimized -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $self,
        '-Worker', '-Hwnd', $Hwnd, '-Log', $Log, '-Hours', $Hours) | Out-Null
    Write-Host "[guard] protecting console window $Hwnd for $Hours h; log: $Log"
    exit 0
}

function Now { Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff' }
function Snapshot([string]$why) {
    $fg = [ConsoleGuard.Native]::GetForegroundWindow()
    $fgPid = 0; [ConsoleGuard.Native]::GetWindowThreadProcessId($fg, [ref]$fgPid) | Out-Null
    $sb = New-Object System.Text.StringBuilder 256
    [ConsoleGuard.Native]::GetWindowText($fg, $sb, 256) | Out-Null
    $fgName = (Get-Process -Id $fgPid -ErrorAction SilentlyContinue).Name
    Add-Content $Log "$(Now) $why foreground=hwnd:$fg pid:$fgPid ($fgName) '$sb'"
    $cut = (Get-Date).AddSeconds(-10)
    Get-CimInstance Win32_Process | ForEach-Object {
        $cd = $null
        try { $cd = [Management.ManagementDateTimeConverter]::ToDateTime($_.CreationDate) } catch {}
        if ($cd -and $cd -gt $cut) {
            $cl = if ($_.CommandLine) { $_.CommandLine.Substring(0, [Math]::Min(160, $_.CommandLine.Length)) } else { '' }
            Add-Content $Log "$(Now)   recent process: $($_.Name) pid=$($_.ProcessId) parent=$($_.ParentProcessId) started=$($cd.ToString('HH:mm:ss')) $cl"
        }
    }
}

$h = [IntPtr]$Hwnd
$last = [ConsoleGuard.Native]::IsWindowVisible($h)
Add-Content $Log "$(Now) guard start hwnd=$Hwnd visible=$last pid=$PID"
$deadline = (Get-Date).AddHours($Hours)
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 250
    if (-not [ConsoleGuard.Native]::IsWindow($h)) { Add-Content $Log "$(Now) window destroyed; guard exiting"; break }
    $v = [ConsoleGuard.Native]::IsWindowVisible($h)
    if ($v -eq $last) { continue }
    if (-not $v) {
        Add-Content $Log "$(Now) WINDOW HIDDEN"
        Snapshot "at hide:"
        Start-Sleep -Milliseconds 1500
        [ConsoleGuard.Native]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE
        Add-Content $Log "$(Now) restored -> visible=$([ConsoleGuard.Native]::IsWindowVisible($h))"
    } else {
        Add-Content $Log "$(Now) window visible again"
    }
    $last = [ConsoleGuard.Native]::IsWindowVisible($h)
}
Add-Content $Log "$(Now) guard end"
