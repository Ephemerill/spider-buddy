param(
    [int]$DesktopSeconds = 1800,
    [int]$HabitatSeconds = 1800,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $root
$dotnet = Join-Path $root ".tools\dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) { $dotnet = "dotnet" }
$appExe = Join-Path $root "src\App\bin\Debug\net10.0-windows\SpiderBuddy.exe"
$data = Join-Path ([IO.Path]::GetTempPath()) ("spider-stage20-gate-" + [Guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force -Path $data | Out-Null
$env:SPIDER_RELEASE_GATE = "1"
$env:SPIDER_DATA = $data
$env:SPIDER_FRAMES = "1"
$env:SPIDER_TIMING = "1"
$env:SPIDER_STATS = "1"
$env:SPIDER_OPEN_TIMING = "1"
$env:SPIDER_OUT = (Join-Path $data "out")

function Step([string]$name, [scriptblock]$run) {
    Write-Host "`n==> $name"
    & $run
    if ($LASTEXITCODE -ne 0) { throw "$name failed with exit code $LASTEXITCODE" }
}

function Start-App([string[]]$appArguments) {
    # Start-Process can return a null ExitCode for a GUI executable. Starting the process
    # directly gives the gate the real exit status after WaitForExit.
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $appExe
    $psi.Arguments = ($appArguments | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' '
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $root
    return [System.Diagnostics.Process]::Start($psi)
}

if (-not $SkipBuild) {
    Step "build app" { & $dotnet build (Join-Path $root "src\App\SpiderBuddy.App.csproj") -v:minimal }
    Step "build tools" { & $dotnet build (Join-Path $root "src\Tools\SpiderBuddy.Tools.csproj") -v:minimal }
}

Step "stage20 harness and release gate" {
    & $dotnet run --project (Join-Path $root "src\Tools\SpiderBuddy.Tools.csproj") -c Debug --no-build -- stage20 gate
}

Step "full habitat soak" {
    & $dotnet run --project (Join-Path $root "src\Tools\SpiderBuddy.Tools.csproj") -c Debug --no-build -- stage20 perch "--habitat-seconds=$HabitatSeconds"
}

Step "built-app Stage 20 smoke" {
    if (-not (Test-Path $appExe)) { throw "Missing app executable: $appExe" }
    $p = Start-App @("--stage20-smoke", "--no-welcome")
    if (-not $p.WaitForExit(300000)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        throw "Stage 20 smoke timed out after 5 minutes"
    }
    $exitCode = $p.ExitCode
    Write-Host "stage20 smoke exit code: $exitCode"
    if ($exitCode -ne 0) { $global:LASTEXITCODE = $exitCode; return }
    $global:LASTEXITCODE = 0
}

Step "desktop frame soak" {
    if (-not (Test-Path $appExe)) { throw "Missing app executable: $appExe" }
    # PowerShell returns immediately when it invokes a GUI executable directly, so the gate
    # must wait for the process itself or it reports success while the soak is still running.
    $p = Start-App @("--desktop-soak=$DesktopSeconds", "--no-welcome")
    $timeoutMs = [Math]::Max(30000, ($DesktopSeconds + 120) * 1000)
    if (-not $p.WaitForExit($timeoutMs)) {
        Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
        throw "Desktop soak did not exit within $($DesktopSeconds + 120)s"
    }
    $exitCode = $p.ExitCode
    Write-Host "desktop soak exit code: $exitCode"
    if ($exitCode -ne 0) { $global:LASTEXITCODE = $exitCode; return }
    $global:LASTEXITCODE = 0
}

$log = Join-Path $data "smoke.log"
if (-not (Test-Path $log)) { throw "Missing app smoke log: $log" }
$soakLine = Get-Content $log | Select-String -Pattern "soak: desktop" | Select-Object -Last 1
if (-not $soakLine) { throw "Desktop soak did not report completion; the gate must not pass" }
$soakText = $soakLine.Line
if ($soakText -match "FAILED") { throw "Desktop soak failed: $soakText" }
if ($soakText -notmatch "soak: desktop ([0-9.]+)s active") { throw "Desktop soak did not report active time: $soakText" }
$reportedSeconds = [double]$Matches[1]
if ($reportedSeconds + 1.5 -lt $DesktopSeconds) { throw "Desktop soak ended early: $soakText" }
$statsLine = Get-Content $log | Select-String -Pattern "stats:" | Select-Object -Last 1
if (-not $statsLine) { throw "Desktop soak did not report a final stats snapshot" }
Write-Host "`n==> last frame meter / stats lines"
Get-Content $log | Select-String -Pattern "meter:|stats:|open:|soak: desktop" | Select-Object -Last 12
Write-Host "`nRELEASE GATE PASSED"
Write-Host "Artifacts: $env:SPIDER_OUT"
Write-Host "Logs: $log"
