# Isolated CoreAudio integration: disposable zero-PCM producers only, never DF.
$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$helper = Join-Path $repo 'build\tools\audio_guard.exe'
$dir = Join-Path $repo ('build\audio-takeover-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $dir | Out-Null
$processes = @()
function Start-Producer([string]$name, [int]$delay=0) {
    $ready = Join-Path $dir ($name + '.ready')
    $proc = Start-Process $helper -ArgumentList ('--silent-producer "{0}" {1}' -f $ready,$delay) -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $dir ($name+'.producer.err'))
    $script:processes += $proc
    if (-not $delay) {
        $deadline=(Get-Date).AddSeconds(10)
        while (-not (Test-Path $ready) -and -not $proc.HasExited -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 50; $proc.Refresh() }
        if (-not (Test-Path $ready)) { throw "Silent audio producer failed: $(Get-Content (Join-Path $dir ($name+'.producer.err')))" }
    }
    return $proc
}
function Probe([System.Diagnostics.Process]$proc) {
    $lines=@(& $helper --probe $proc.Id)
    if ($LASTEXITCODE -ne 0) { throw "No test session for pid $($proc.Id)" }
    return $lines -join ';'
}
$parentScript = Join-Path $dir 'parent.ps1'
@'
param($Module,$Helper,$TargetId,$Ready,$Finish,$Journal)
$ErrorActionPreference='Stop'
Import-Module $Module
$guard=$null
try {
 $guard=Start-DfAudioTakeover -Helper $Helper -DfProcess (Get-Process -Id $TargetId)
 [IO.File]::WriteAllText($Journal,$guard.Directory)
 [IO.File]::WriteAllText($Ready,'ready')
 while(-not (Test-Path $Finish)){Assert-DfAudioTakeover $guard;Start-Sleep -Milliseconds 100}
} finally {Stop-DfAudioTakeover $guard}
'@ | Set-Content -Encoding utf8 $parentScript
try {
    $unrelated = Start-Producer 'unrelated'
    $unrelatedBefore = Probe $unrelated
    # A PID with the wrong creation time must be rejected before any mute write.
    $identityArgs='--guard {0} {1} {2} 0 "{3}\identity.status" "{3}\identity.stop"' -f $PID,(Get-Process -Id $PID).StartTime.ToFileTimeUtc(),$unrelated.Id,$dir
    $invalid=Start-Process $helper -ArgumentList $identityArgs -WindowStyle Hidden -Wait -PassThru -RedirectStandardError (Join-Path $dir 'identity.err')
    if ($invalid.ExitCode -ne 1 -or (Probe $unrelated) -ne $unrelatedBefore) { throw 'Process identity guard failed' }
    Write-Host 'audio takeover PASS: wrong process creation identity rejected without changing mute'
    foreach ($scenario in @('normal','abrupt','muted','late','external-unmute')) {
        $target = Start-Producer $scenario $(if($scenario -eq 'late'){4000}else{0})
        if($scenario -eq 'muted'){ & $helper --test-mute $target.Id; if($LASTEXITCODE){throw 'test mute failed'} }
        $before = if($scenario -eq 'late'){'mute=0 volume=1'}else{Probe $target}
        $ready=Join-Path $dir ($scenario+'.parent-ready'); $finish=Join-Path $dir ($scenario+'.finish'); $journal=Join-Path $dir ($scenario+'.journal')
        $arguments='-NoProfile -ExecutionPolicy Bypass -File "{0}" -Module "{1}\AudioTakeover.psm1" -Helper "{2}" -TargetId {3} -Ready "{4}" -Finish "{5}" -Journal "{6}"' -f $parentScript,$PSScriptRoot,$helper,$target.Id,$ready,$finish,$journal
        $parent=Start-Process powershell -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $dir ($scenario+'.log')) -RedirectStandardError (Join-Path $dir ($scenario+'.err'))
        $processes += $parent
        $deadline=(Get-Date).AddSeconds(15)
        while (-not (Test-Path $ready) -and -not $parent.HasExited -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 50;$parent.Refresh()}
        if(-not (Test-Path $ready)){throw "Guardian parent failed for $scenario"}
        if($scenario -eq 'late'){Start-Sleep -Seconds 5}
        $during=Probe $target
        if($during -notmatch 'mute=1'){throw "Selected session was not muted: $during"}
        if((Probe $unrelated) -ne $unrelatedBefore){throw 'Unrelated session changed'}
        if($scenario -eq 'external-unmute'){
            & $helper --test-unmute $target.Id
            Start-Sleep -Milliseconds 750
            if((Probe $target) -ne $before){throw 'Guardian overwrote an external unmute'}
        }
        if($scenario -eq 'abrupt'){Stop-Process -Id $parent.Id -Force}else{[IO.File]::WriteAllText($finish,'stop')}
        if(-not $parent.WaitForExit(15000)){throw 'Guardian parent did not exit'}
        $deadline=(Get-Date).AddSeconds(10)
        do {Start-Sleep -Milliseconds 100;$after=Probe $target} while($after -ne $before -and (Get-Date) -lt $deadline)
        if($after -ne $before){throw "Session not restored: before=$before after=$after"}
        if((Probe $unrelated) -ne $unrelatedBefore){throw 'Unrelated session changed on restoration'}
        Write-Host "audio takeover PASS: $scenario; before=$before during=$during after=$after; unrelated unchanged"
        Stop-Process -Id $target.Id -Force
    }
} finally {
    foreach($proc in $processes){$proc.Refresh();if(-not $proc.HasExited){Stop-Process -Id $proc.Id -Force}}
}
