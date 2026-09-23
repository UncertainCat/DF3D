# The guardian deliberately does not join the DF/Godot job: it must restore
# the external DF audio after that job's owner crashes or is terminated.
function Start-DfAudioTakeover {
    param([string]$Helper, [System.Diagnostics.Process]$DfProcess)
    if (-not (Test-Path -LiteralPath $Helper)) { throw 'Audio guardian is not built. Run cmake --build build --target audio_guard before Play.' }
    $dir = Join-Path ([IO.Path]::GetTempPath()) ('df3d-audio-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $status = Join-Path $dir 'status'
    $stop = Join-Path $dir 'stop'
    $parent = Get-Process -Id $PID
    $argsText = '--guard {0} {1} {2} {3} "{4}" "{5}"' -f $PID, $parent.StartTime.ToFileTimeUtc(), $DfProcess.Id, $DfProcess.StartTime.ToFileTimeUtc(), $status, $stop
    $proc = Start-Process -FilePath $Helper -ArgumentList $argsText -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $dir 'error.log')
    $guard = [pscustomobject]@{ Process=$proc; Directory=$dir; Status=$status; Stop=$stop }
    try {
        $deadline = (Get-Date).AddSeconds(15)
        while (-not (Test-Path -LiteralPath $status) -and -not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50; $proc.Refresh() }
        $message = if (Test-Path -LiteralPath $status) { [IO.File]::ReadAllText($status).Trim() } else { 'No readiness response' }
        if ($message -ne 'READY' -or $proc.HasExited) { throw "Audio takeover failed: $message. Details: $dir" }
        return $guard
    } catch {
        Stop-DfAudioTakeover $guard
        throw
    }
}

function Assert-DfAudioTakeover {
    param($Guard)
    $Guard.Process.Refresh()
    if ($Guard.Process.HasExited) {
        $message = if (Test-Path -LiteralPath $Guard.Status) { [IO.File]::ReadAllText($Guard.Status).Trim() } else { 'Guardian exited unexpectedly' }
        throw "Audio takeover stopped: $message. Closing viewer; details: $($Guard.Directory)"
    }
}

function Stop-DfAudioTakeover {
    param($Guard)
    if (-not $Guard) { return }
    [IO.File]::WriteAllText($Guard.Stop, 'stop')
    if (-not $Guard.Process.WaitForExit(10000)) {
        Write-Warning "Audio guardian has not finished restoring DF. It remains running; check Windows Volume Mixer and $($Guard.Directory)."
        return
    }
    $message = if (Test-Path -LiteralPath $Guard.Status) { [IO.File]::ReadAllText($Guard.Status).Trim() } else { 'Missing restoration status' }
    if ($message -ne 'RESTORED') { Write-Warning "Audio restoration: $message. Check Windows Volume Mixer. Details: $($Guard.Directory)" }
    else {
        # Only this invocation's explicit files; no recursive computed deletion.
        Remove-Item -LiteralPath $Guard.Status, $Guard.Stop, (Join-Path $Guard.Directory 'error.log') -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $Guard.Directory -ErrorAction SilentlyContinue
    }
}
Export-ModuleMember -Function Start-DfAudioTakeover, Assert-DfAudioTakeover, Stop-DfAudioTakeover
