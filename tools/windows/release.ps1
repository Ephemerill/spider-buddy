param(
    [switch]$Publish,
    [switch]$SkipSign,
    [switch]$AllowDirty,
    [string]$Notes = "notes.md",
    [string]$KeyFile = "",
    [string]$Thumbprint = $env:SPIDER_SIGN_THUMBPRINT,
    [string]$Pfx = $env:SPIDER_SIGN_PFX,
    [string]$PfxPassword = $env:SPIDER_SIGN_PFX_PASSWORD,
    [string]$Repo = "Ephemerill/spider-buddy"
)

$ErrorActionPreference = "Stop"
$root = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
Set-Location $root
$dotnet = Join-Path $root ".tools\dotnet\dotnet.exe"
if (-not (Test-Path $dotnet)) { $dotnet = "dotnet" }
$version = (Get-Content (Join-Path $root "VERSION") -Raw).Trim()
$tag = "v$version"
if (-not $KeyFile) { $KeyFile = Join-Path $root "build\windows\keys\windows-update-key.json" }
$publicFile = Join-Path $root "Resources\WindowsUpdatePublicKey.txt"
$installer = Join-Path $root "build\windows\installer\SpiderBuddy-$version-setup.exe"
$appcast = Join-Path $root "build\windows\windows-appcast.xml"

if ($Publish -and -not $AllowDirty) {
    $dirty = git status --porcelain
    if ($LASTEXITCODE -ne 0) { throw "git status failed" }
    if ($dirty) { throw "Commit and push the version, source and generated assets before publishing (or pass -AllowDirty)." }
}

Write-Host "==> Building and packaging $tag"
$packageArgs = @{ Thumbprint = $Thumbprint; Pfx = $Pfx; PfxPassword = $PfxPassword }
if ($SkipSign) { $packageArgs.SkipSign = $true }
& (Join-Path $PSScriptRoot "package.ps1") @packageArgs
if (-not (Test-Path $installer)) { throw "Missing installer: $installer" }

if (-not (Test-Path $KeyFile)) {
    throw "The Windows update private key is missing. Run: dotnet run --project src/Tools/SpiderBuddy.Tools.csproj -- update-key --key `"$KeyFile`" --public-file `"$publicFile`" and rebuild the app."
}
& $dotnet run --project (Join-Path $root "src\Tools\SpiderBuddy.Tools.csproj") -c Release --no-launch-profile -- update-key --key $KeyFile --public-file $publicFile | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Could not read the update key" }
$publicKey = (Get-Content $publicFile -Raw).Trim()
if ($publicKey -notmatch '^[A-Za-z0-9+/]{43}=$') { throw "The public update key file is invalid" }

$appExe = Join-Path $root "build\windows\publish\SpiderBuddy.exe"
if (-not (Test-Path $appExe)) { throw "The published app is missing; package.ps1 must run before signing the appcast." }
# The app embeds the public key at compile time. Rebuild if it changed after publish.
$oldPublic = $env:SPIDER_UPDATE_PUBLIC_KEY
$env:SPIDER_UPDATE_PUBLIC_KEY = $null
$embedded = (& $appExe --update-public-key 2>$null | Select-Object -First 1).Trim()
if ($oldPublic) { $env:SPIDER_UPDATE_PUBLIC_KEY = $oldPublic }
if ($embedded -ne $publicKey) {
    throw "The app was built with a different update public key. Rebuild after restoring the key, then rerun."
}
& $dotnet run --project (Join-Path $root "src\Tools\SpiderBuddy.Tools.csproj") -c Release --no-launch-profile -- sign-appcast --key $KeyFile --installer $installer --version $version --url "https://github.com/$Repo/releases/download/$tag/SpiderBuddy-$version-setup.exe" --notes-file $Notes --output $appcast
if ($LASTEXITCODE -ne 0) { throw "Appcast signing failed" }
if (-not (Test-Path $appcast)) { throw "The appcast was not written" }
& $dotnet run --project (Join-Path $root "src\Tools\SpiderBuddy.Tools.csproj") -c Release --no-launch-profile -- verify-appcast --feed $appcast --key $KeyFile | Out-Host
if ($LASTEXITCODE -ne 0) { throw "The generated appcast failed verification" }

Write-Host "==> Appcast: $appcast"
if (-not $Publish) {
    Write-Host "Local package complete. Re-run with -Publish to create the GitHub release and publish the appcast."
    exit 0
}

if ($SkipSign) { throw "Refusing to publish an unsigned build." }
$installerSignature = Get-AuthenticodeSignature $installer
$appSignature = Get-AuthenticodeSignature $appExe
if ($installerSignature.Status -ne 'Valid' -or $appSignature.Status -ne 'Valid') {
    throw "Refusing to publish an untrusted signature (installer: $($installerSignature.Status), app: $($appSignature.Status)). Use a trusted code-signing certificate."
}
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "GitHub CLI (gh) is required to publish." }
$portable = Join-Path $root "build\windows\installer\SpiderBuddy-$version-portable.zip"
$notesPath = if (Test-Path $Notes) { (Resolve-Path $Notes).Path } else { $null }
$existingRelease = & gh release view $tag --repo $Repo 2>$null
$releaseExists = $LASTEXITCODE -eq 0 -and $existingRelease
if ($releaseExists) {
    # v1.0.1 already exists as the Mac release. Add the Windows assets to that
    # release rather than creating a second release for the same tag.
    Write-Host "==> Adding Windows assets to the existing release $tag"
    & gh release upload $tag $installer $portable --repo $Repo --clobber
    if ($LASTEXITCODE -ne 0) { throw "gh release upload failed" }
} else {
    $releaseArgs = @("release", "create", $tag, $installer, $portable, "--repo", $Repo, "--title", "Spider Buddy $version for Windows", "--notes-file", $notesPath)
    if (-not $notesPath) { $releaseArgs = @("release", "create", $tag, $installer, $portable, "--repo", $Repo, "--title", "Spider Buddy $version for Windows", "--generate-notes") }
    Write-Host "==> Creating the GitHub release $tag"
    & gh @releaseArgs
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }
}

Write-Host "==> Publishing windows-appcast.xml to the gh-pages branch"
$content = [Convert]::ToBase64String([IO.File]::ReadAllBytes($appcast))
$existing = & gh api "repos/$Repo/contents/windows-appcast.xml?ref=gh-pages" 2>$null
$sha = $null
if ($LASTEXITCODE -eq 0 -and $existing) { $sha = ($existing | ConvertFrom-Json).sha }
$apiArgs = @("api", "repos/$Repo/contents/windows-appcast.xml", "-X", "PUT", "-f", "message=Update Windows appcast for $tag", "-f", "content=$content", "-f", "branch=gh-pages")
if ($sha) { $apiArgs += @("-f", "sha=$sha") }
& gh @apiArgs | Out-Host
if ($LASTEXITCODE -ne 0) { throw "Publishing the Windows appcast failed" }
Write-Host "Published $tag and the Windows appcast."
