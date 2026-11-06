param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [switch]$ExpectSigned
)

$ErrorActionPreference = "Stop"
$installer = (Resolve-Path -LiteralPath $Installer).Path
$version = (Get-Content (Join-Path $PSScriptRoot "..\..\VERSION") -Raw).Trim()
$installDir = Join-Path $env:TEMP ("spider-buddy-install-test-" + [Guid]::NewGuid().ToString("N"))
$uninstallKey = $null
$shortcutDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Spider Buddy"

function Fail([string]$message) { throw "INSTALL TEST FAILED: $message" }

try {
    $signature = Get-AuthenticodeSignature $installer
    if ($ExpectSigned) {
        if ($signature.Status -eq 'NotSigned') { Fail "installer is not Authenticode-signed" }
        Write-Host "Installer signature: $($signature.Status) - $($signature.SignerCertificate.Subject)"
    } else {
        Write-Host "Installer signature: $($signature.Status) (expected for an unsigned test build)"
    }

    Write-Host "==> Installing silently to $installDir"
    $process = Start-Process -FilePath $installer -Wait -PassThru -ArgumentList @(
        "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/NOAPP", "/DIR=$installDir"
    )
    if ($process.ExitCode -ne 0) { Fail "installer exited $($process.ExitCode)" }

    $exe = Join-Path $installDir "SpiderBuddy.exe"
    foreach ($path in @(
        $exe,
        (Join-Path $installDir "Extension\manifest.json"),
        (Join-Path $installDir "AppIcon.ico"),
        (Join-Path $installDir "unins000.exe")
    )) {
        if (-not (Test-Path -LiteralPath $path)) { Fail "missing installed file: $path" }
    }
    $installedVersion = (Get-Content (Join-Path $installDir "VERSION") -Raw).Trim()
    if ($installedVersion -ne $version) { Fail "installed app version is $installedVersion, expected $version" }

    $uninstallKey = Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" |
        Where-Object { (Get-ItemProperty $_.PSPath).DisplayName -like "Spider Buddy*" } |
        Select-Object -First 1
    if (-not $uninstallKey) { Fail "no HKCU uninstall entry was registered" }
    $entry = Get-ItemProperty $uninstallKey.PSPath
    if ($entry.DisplayVersion -ne $version) { Fail "uninstall entry version is $($entry.DisplayVersion)" }
    if ($entry.InstallLocation.TrimEnd('\') -ne $installDir.TrimEnd('\')) { Fail "uninstall entry points at $($entry.InstallLocation)" }
    if ($entry.UninstallString -notmatch 'unins000\.exe') { Fail "uninstall string is not the per-user uninstaller" }
    Write-Host "HKCU entry: $($entry.DisplayName) $($entry.DisplayVersion) at $($entry.InstallLocation)"

    if (Test-Path -LiteralPath $shortcutDir) {
        Write-Host "Start-menu shortcut directory: $shortcutDir"
    }

    Write-Host "==> Launching the installed app update-key self check"
    $key = (& $exe --update-public-key 2>$null | Select-Object -First 1).Trim()
    $expectedKey = (Get-Content (Join-Path $PSScriptRoot "..\..\Resources\WindowsUpdatePublicKey.txt") -Raw).Trim()
    if ($key -ne $expectedKey) { Fail "installed app reports the wrong update key" }

    Write-Host "==> Running the installed app smoke test"
    $data = Join-Path $env:TEMP ("spider-buddy-install-data-" + [Guid]::NewGuid().ToString("N"))
    $oldData = $env:SPIDER_DATA
    $env:SPIDER_DATA = $data
    try {
        $smoke = Start-Process -FilePath $exe -Wait -PassThru -ArgumentList @("--smoke", "--no-welcome")
        if ($smoke.ExitCode -ne 0) { Fail "installed app smoke exited $($smoke.ExitCode)" }
    } finally {
        if ($oldData) { $env:SPIDER_DATA = $oldData } else { Remove-Item Env:\SPIDER_DATA -ErrorAction SilentlyContinue }
        if (Test-Path $data) { Remove-Item $data -Recurse -Force -ErrorAction SilentlyContinue }
    }
    Write-Host "Installed app smoke: OK"

    Write-Host "==> Uninstalling"
    $uninstaller = Join-Path $installDir "unins000.exe"
    $uninstall = Start-Process -FilePath $uninstaller -Wait -PassThru -ArgumentList @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART")
    if ($uninstall.ExitCode -ne 0) { Fail "uninstaller exited $($uninstall.ExitCode)" }
    Start-Sleep -Milliseconds 700
    if (Test-Path -LiteralPath $installDir) { Fail "install directory survived uninstall: $installDir" }
    if (Get-ChildItem "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall" -ErrorAction SilentlyContinue |
        Where-Object { (Get-ItemProperty $_.PSPath).DisplayName -like "Spider Buddy*" }) {
        Fail "HKCU uninstall entry survived uninstall"
    }
    Write-Host "Uninstall: OK"
    Write-Host "INSTALL TEST PASSED"
} catch {
    Write-Host $_.Exception.Message
    if (Test-Path -LiteralPath $installDir) {
        Write-Host "Install directory left for inspection: $installDir"
    }
    exit 1
}
