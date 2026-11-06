# Releasing Spider Buddy for Windows

This is the Windows release path. The Mac path is still [RELEASING.md](RELEASING.md).

## What ships

- `SpiderBuddy-<version>-setup.exe` — Inno Setup 6, per user under
  `%LOCALAPPDATA%\Programs\SpiderBuddy`, no administrator prompt, with Start-menu and optional
  desktop shortcuts, an uninstall entry in HKCU, the app icon, installer artwork, and the browser
  extension under `Extension\`.
- `SpiderBuddy-<version>-portable.zip` — the same published files, for people who do not want an
  installer.
- `windows-appcast.xml` — a small signed feed served from
  **https://ephemerill.github.io/spider-buddy/windows-appcast.xml**. That address is compiled into
  every copy and must never move. It is the Windows counterpart of the Mac appcast, with its own
  Ed25519 key.

## Requirements

- .NET 10 SDK (the repo's `.tools/dotnet` works).
- Inno Setup 6. Install per user with:
  `winget install JRSoftware.InnoSetup --scope user`
- PowerShell 5.1+ on Windows.
- An Authenticode code-signing certificate (EV or a certificate usable with
  `Set-AuthenticodeSignature`) in `Cert:\CurrentUser\My`, or a PFX. The release path refuses to
  build without one; use `-SkipSign` only for a local test build.
- For `-Publish`: GitHub CLI (`gh`) authenticated, and a `gh-pages` branch containing the Mac
  appcast. The Windows release script expects that branch to exist.

## Keys

The Windows update key is **separate from Sparkle's Mac key**:

- Private: `build/windows/keys/windows-update-key.json` (ignored by git).
- Public: `Resources/WindowsUpdatePublicKey.txt`, embedded in the app as
  `SpiderBuddy.UpdatePublicKey`.

**Back up the private key somewhere safe.** Losing it means every installed Windows copy stops
being able to update; replacing the public key requires shipping a new build. Do not put the
private key in the repository, a release asset, chat, or a log. To print the public key without
revealing the private one:

```powershell
dotnet run --project src/Tools/SpiderBuddy.Tools.csproj -- update-key `
  --key build/windows/keys/windows-update-key.json `
  --public-file Resources/WindowsUpdatePublicKey.txt
```

The app only ever contains the public key. The release script checks that the published executable
and `Resources/WindowsUpdatePublicKey.txt` agree before it signs a feed.

## Signing

The scripts use Windows' own Authenticode support, so no `signtool` installation is required. Set
one of these before a release:

```powershell
$env:SPIDER_SIGN_THUMBPRINT = "ABCDEF..."       # certificate in Cert:\CurrentUser\My
# or
$env:SPIDER_SIGN_PFX = "C:\secure\spider.pfx"
$env:SPIDER_SIGN_PFX_PASSWORD = "..."
```

`SPIDER_TIMESTAMP_URL` defaults to `http://timestamp.digicert.com`. The app executable is signed
before packaging, then the setup executable is signed. The setup is what the appcast points at.

A temporary self-signed certificate is useful for verifying the pipeline, but Windows will report
an unknown publisher and SmartScreen will not be satisfied. Only an EV or trusted code-signing
certificate removes that warning.

## Local test build

```powershell
# optional: regenerate packaging/installer-art.bmp and installer-small.bmp
.\tools\windows\make-installer-art.ps1

# unsigned local package (explicitly refuses to be called a release)
.\tools\windows\package.ps1 -SkipSign

# install into a temporary directory, run the app's smoke test, then uninstall
.\tools\windows\test-install.ps1 `
  -Installer .\build\windows\installer\SpiderBuddy-1.0.1-setup.exe
```

`package.ps1` publishes a self-contained `win-x64` app, copies `VERSION` into the package, strips
PDB/XML debug files, checks the embedded update key, builds the installer, and writes
`build/windows/installer/package.json` with the installer's SHA-256. `test-install.ps1` verifies
the HKCU registration, installed files and shortcut directory, runs the installed app with an
isolated `SPIDER_DATA`, and checks that uninstall removes the directory and registry entry.

To exercise the signed path without a production certificate, create a temporary code-signing
certificate and build:

```powershell
$cert = New-SelfSignedCertificate -Type CodeSigningCert `
  -Subject "CN=Spider Buddy test" -CertStoreLocation Cert:\CurrentUser\My
$env:SPIDER_SIGN_THUMBPRINT = $cert.Thumbprint
.\tools\windows\release.ps1 -Notes .\out\notes.md
```

## The release

1. Bump `VERSION` and add the release notes to a markdown file. Notes before
   `<!-- install -->` are the "What's new" text in the update window; text after the marker is for
   people downloading manually and is not included in the appcast.
2. Commit and push the version, sources and generated resources.
3. Run locally first:

   ```powershell
   .\tools\windows\release.ps1 -Notes .\notes.md
   ```

4. Publish only when authorized:

   ```powershell
   .\tools\windows\release.ps1 -Notes .\notes.md -Publish
   ```

The script builds → packages → checks the key and signature → writes and verifies the appcast →
creates the GitHub release tagged `v<VERSION>` with the setup and portable zip, or adds both
assets to an existing release for that tag (v1.0.1 is already the Mac release) → uploads
`windows-appcast.xml` to `gh-pages` through the GitHub API. The release assets are in place before
the appcast is published, so the feed never points at a missing asset. It refuses to publish a
dirty working tree unless `-AllowDirty` is passed, refuses an untrusted signature, and refuses to
publish an unsigned build.

The appcast and installer are both Ed25519-signed with the Windows key. The feed signature covers
the version, URL, byte length, installer signature and notes. The app verifies the feed, then
verifies the downloaded installer, before it runs anything. Installed copies check daily; a found
update waits as **Update to x.y.z** on the first panel page. With **Install Automatically (on
quit)** on, a downloaded, verified update is installed when the app quits. `SPIDER_UPDATE_TEST=1`
starts the check 800 ms after launch for testing.

## Verification recorded for Stage 19

- `tools stage19` — 34/34 checks.
- `SpiderBuddy.exe --stage19-smoke --no-welcome` — 15/15 checks, including a signed appcast over
  loopback, installer download, signature verification and tamper rejection.
- Installer compile, silent per-user install, HKCU entry, installed app smoke and uninstall —
  passed.
- Authenticode signing path tested with a temporary self-signed certificate (status
  `UnknownError` because the test root is untrusted, as expected).
- A local release run created and verified the appcast; its notes correctly stopped at
  `<!-- install -->`.
- **Not done here:** production code signing and a public release. No EV/Azure Trusted Signing
  certificate is available on this machine, and no release was published.
