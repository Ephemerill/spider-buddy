# Laptop side of `lap run` / `lap shot`. SSH lands in session 0, which has no desktop: a GUI started there
# is invisible and cannot see other windows. These helpers start things in the person's real session
# through a one-shot scheduled task, under a headless conhost so no console window flashes or takes focus.
# (VBScript stubs do not work on this build: do not go back to them.)
$ErrorActionPreference = 'Stop'
$BridgeDir = 'C:\Users\User\AppData\Local\Temp\spider-bridge'
New-Item -ItemType Directory -Force -Path $BridgeDir | Out-Null

function Start-InSession([string]$Ps1, [string]$Name) {
    $task = "SpiderBridge-$Name"
    $a = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$Ps1`""
    $p = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
    $s = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 4) -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $task -Action $a -Principal $p -Settings $s -Force | Out-Null
    Start-ScheduledTask -TaskName $task
    Start-Sleep -Milliseconds 1500
    Unregister-ScheduledTask -TaskName $task -Confirm:$false
}

function Invoke-Bridge([string]$Repo, [string]$Exe, [string]$ExeArgs, [string]$EnvList, [string]$Log, [int]$Wait) {
    $logFile = Join-Path $BridgeDir "$Log.log"
    $doneFile = Join-Path $BridgeDir "$Log.done"
    Remove-Item $logFile, $doneFile -ErrorAction SilentlyContinue
    $path = if ([IO.Path]::IsPathRooted($Exe)) { $Exe } else { Join-Path $Repo $Exe }
    $envLines = ($EnvList -split ';' | Where-Object { $_ } | ForEach-Object {
        $kv = $_ -split '=', 2; "`$env:$($kv[0]) = '$($kv[1])'"
    }) -join "`n"
    $runner = Join-Path $BridgeDir "$Log.run.ps1"
    @"
Set-Location '$Repo'
`$env:DOTNET_ROOT = '$Repo\.tools\dotnet'
`$env:PATH = "`$env:LOCALAPPDATA\Programs\Swift\Runtimes\6.4.2\usr\bin;`$env:PATH"
$envLines
`$psi = New-Object Diagnostics.ProcessStartInfo
`$psi.FileName = '$path'
`$psi.Arguments = '$ExeArgs'
`$psi.UseShellExecute = `$false
`$psi.RedirectStandardOutput = `$true
`$psi.RedirectStandardError = `$true
`$psi.CreateNoWindow = `$true
foreach (`$k in [Environment]::GetEnvironmentVariables().Keys) { `$psi.EnvironmentVariables[`$k] = [Environment]::GetEnvironmentVariable(`$k) }
`$p = New-Object Diagnostics.Process
`$p.StartInfo = `$psi
`$w = [IO.StreamWriter]::new('$logFile', `$false)
`$w.AutoFlush = `$true
Register-ObjectEvent `$p OutputDataReceived -Action { `$Event.MessageData.WriteLine(`$EventArgs.Data) } -MessageData `$w | Out-Null
Register-ObjectEvent `$p ErrorDataReceived -Action { `$Event.MessageData.WriteLine(`$EventArgs.Data) } -MessageData `$w | Out-Null
[void]`$p.Start()
`$p.BeginOutputReadLine(); `$p.BeginErrorReadLine()
while (-not `$p.HasExited) { Start-Sleep -Milliseconds 200 }
Start-Sleep -Milliseconds 300
`$w.Dispose()
"exit=`$(`$p.ExitCode)" | Out-File '$doneFile' -Encoding ascii
"@ | Out-File $runner -Encoding utf8
    Start-InSession $runner $Log
    if ($Wait -gt 0) {
        $deadline = (Get-Date).AddSeconds($Wait)
        while ((Get-Date) -lt $deadline -and -not (Test-Path $doneFile)) { Start-Sleep -Milliseconds 300 }
        if (Test-Path $logFile) { Get-Content $logFile -ErrorAction SilentlyContinue }
        if (Test-Path $doneFile) { Get-Content $doneFile } else { "still running after $Wait s (log: $Log)" }
    } else { "started (log: $Log)" }
}

function Invoke-Shot([string]$Rect) {
    $out = Join-Path $BridgeDir 'shot.png'
    Remove-Item $out -ErrorAction SilentlyContinue
    $runner = Join-Path $BridgeDir 'shot.run.ps1'
    @"
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class ShotNative {
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int i);
}
'@
[ShotNative]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
Add-Type -AssemblyName System.Drawing
`$r = '$Rect' -split ' ' | Where-Object { `$_ }
if (`$r.Count -eq 4) { `$x=[int]`$r[0]; `$y=[int]`$r[1]; `$w=[int]`$r[2]; `$h=[int]`$r[3] }
else { `$x=[ShotNative]::GetSystemMetrics(76); `$y=[ShotNative]::GetSystemMetrics(77); `$w=[ShotNative]::GetSystemMetrics(78); `$h=[ShotNative]::GetSystemMetrics(79) }
`$b = New-Object Drawing.Bitmap `$w,`$h
`$g = [Drawing.Graphics]::FromImage(`$b)
`$g.CopyFromScreen(`$x,`$y,0,0,(New-Object Drawing.Size `$w,`$h))
`$b.Save('$out')
"@ | Out-File $runner -Encoding utf8
    Start-InSession $runner 'shot'
    $deadline = (Get-Date).AddSeconds(15)
    while ((Get-Date) -lt $deadline -and -not (Test-Path $out)) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path $out)) { throw 'screenshot did not appear (screen locked or asleep?)' }
}
