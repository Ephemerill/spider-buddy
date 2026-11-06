param(
    [string]$Configuration = "Release",
    [string]$Runtime = "win-x64",
    [switch]$SkipSign,
    [string]$Thumbprint = $env:SPIDER_SIGN_THUMBPRINT,
    [string]$Pfx = $env:SPIDER_SIGN_PFX,
    [string]$PfxPassword = $env:SPIDER_SIGN_PFX_PASSWORD
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $root
$dotnet = Join-Path $root ".tools\dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) { $dotnet = "dotnet" }
$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+') { throw "VERSION is not a three-part version: $version" }
$publishDir = Join-Path $root "build\windows\publish"
$installerDir = Join-Path $root "build\windows\installer"
$portableDir = Join-Path $root "build\windows\portable"
$installer = Join-Path $installerDir "SpiderBuddy-$version-setup.exe"
$portable = Join-Path $installerDir "SpiderBuddy-$version-portable.zip"

if (Test-Path $publishDir) { Remove-Item $publishDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $publishDir, $installerDir | Out-Null

Write-Host "==> Publishing $version ($Runtime, self-contained)"
& $dotnet publish (Join-Path $root "src\App\SpiderBuddy.App.csproj") `
    -c $Configuration -r $Runtime --self-contained true `
    -p:Version=$version -p:DebugType=None -p:DebugSymbols=false `
    -p:PublishTrimmed=false -o $publishDir
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed with exit code $LASTEXITCODE" }
$exe = Join-Path $publishDir "SpiderBuddy.exe"
if (-not (Test-Path $exe)) { throw "The published app has no SpiderBuddy.exe" }
if (-not (Test-Path (Join-Path $publishDir "Extension\manifest.json"))) { throw "The extension was not published with the app" }
Get-ChildItem $publishDir -Recurse -Include *.pdb, *.xml | Remove-Item -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $root "VERSION") (Join-Path $publishDir "VERSION") -Force
$publicKey = (Get-Content (Join-Path $root "Resources\WindowsUpdatePublicKey.txt") -Raw).Trim()
$embeddedKey = (& $exe --update-public-key 2>$null | Select-Object -First 1).Trim()
if ($embeddedKey -ne $publicKey) { throw "The published app embedded key does not match Resources\WindowsUpdatePublicKey.txt" }

if (-not $SkipSign) {
    if (-not $Thumbprint -and -not $Pfx) {
        throw "Refusing to package an unsigned release. Set SPIDER_SIGN_THUMBPRINT or SPIDER_SIGN_PFX, or pass -SkipSign for a local test build."
    }
    Write-Host "==> Signing the app executable"
    & (Join-Path $PSScriptRoot "sign.ps1") -File $exe -Thumbprint $Thumbprint -Pfx $Pfx -PfxPassword $PfxPassword
}

$isccCandidates = @(
    $env:INNO_SETUP_ISCC,
    (Join-Path $env:LOCALAPPDATA "Programs\Inno Setup 6\ISCC.exe"),
    (Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe"),
    (Join-Path $env:ProgramFiles "Inno Setup 6\ISCC.exe")
) | Where-Object { $_ -and (Test-Path $_) }
$iscc = $isccCandidates | Select-Object -First 1
if (-not $iscc) { throw "Inno Setup 6 was not found. Install it per-user with: winget install JRSoftware.InnoSetup --scope user" }

Write-Host "==> Building the per-user installer with Inno Setup"
& $iscc "/DMyAppVersion=$version" "/DSourceDir=$publishDir" (Join-Path $root "packaging\SpiderBuddy.iss")
if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE" }
if (-not (Test-Path $installer)) { throw "Inno Setup did not produce $installer" }

if (-not $SkipSign) {
    Write-Host "==> Signing the installer"
    & (Join-Path $PSScriptRoot "sign.ps1") -File $installer -Thumbprint $Thumbprint -Pfx $Pfx -PfxPassword $PfxPassword
    $signature = Get-AuthenticodeSignature $installer
    if ($signature.Status -notin @('Valid', 'UnknownError')) { throw "The installer signature is not valid: $($signature.Status)" }
}

Write-Host "==> Building the portable zip"
if (Test-Path $portableDir) { Remove-Item $portableDir -Recurse -Force }
Copy-Item $publishDir $portableDir -Recurse -Force
if (Test-Path $portable) { Remove-Item $portable -Force }
Compress-Archive -Path (Join-Path $portableDir "*") -DestinationPath $portable -CompressionLevel Optimal

$manifest = [ordered]@{
    version = $version
    runtime = $Runtime
    installer = $installer
    installerBytes = (Get-Item $installer).Length
    installerSha256 = (Get-FileHash $installer -Algorithm SHA256).Hash.ToLowerInvariant()
    portable = $portable
    signed = (-not $SkipSign)
    builtUtc = [DateTime]::UtcNow.ToString("o")
}
$manifest | ConvertTo-Json | Set-Content (Join-Path $installerDir "package.json") -Encoding UTF8
Write-Host "==> Installer: $installer"
Write-Host "==> Portable:  $portable"
if ($SkipSign) { Write-Warning "This is an unsigned local test build; do not publish it." }
