# Releasing Spider Buddy

How a version goes from this repo to people's Macs. Everything is driven by
`tools/release.sh`; this is what it does and what it needs.

## Cutting a release

```bash
echo 0.9.0 > VERSION                         # minor bump for feature releases
export GH_TOKEN="$(printf 'protocol=https\nhost=github.com\n' | git credential fill | sed -n 's/^password=//p')"
NOTES=notes.md tools/release.sh --publish    # notes.md = the "What's new" (optional)
```

Run `tools/release.sh` without `--publish` first to build, notarize and package
locally without making anything public. The tag is always `v<VERSION>`.

Commit the version bump and built binaries as usual (`git add -A`); the `.dmg`,
`Spider Buddy.app` and `build/appcast.xml` are git-ignored.

## The pipeline

1. **Preflight.** Finds the `Developer ID Application` certificate in the
   keychain and checks the notarytool credentials (`spider-notary`). If either
   is missing it stops before building.
2. **Build.** `build.sh` compiles `Spider Buddy.app` and bundles
   Sparkle.framework (fetched once into `build/Sparkle` by `tools/sparkle.sh`).
3. **Sign.** With `SIGN_IDENTITY` set, `build.sh` signs inside-out with the
   hardened runtime and a secure timestamp: Sparkle's `Installer.xpc`,
   `Downloader.xpc` (keeping its entitlements), `Autoupdate`, `Updater.app`,
   the framework, then the app. The app needs no entitlements.
4. **Notarize the app.** Zips it, submits it to Apple with
   `notarytool submit --wait`, then staples the ticket to the app, so the copy
   dragged out of the `.dmg` (or installed by Sparkle) works offline.
5. **Package.** Builds `build/SpiderBuddy-<VERSION>.dmg` (app and an
   Applications link).
6. **Notarize the .dmg.** Signs it, submits it, staples it, and checks both
   the `.dmg` and the app with `spctl` (Gatekeeper).
7. **Appcast.** Signs the `.dmg` with the Sparkle EdDSA key, writes
   `build/appcast.xml` (the notes before `<!-- install -->` show in the update
   window), and signs the feed itself.
8. **Publish** (`--publish` only). Creates the GitHub release with the `.dmg`
   (or replaces the `.dmg` if the release exists), then PUTs `appcast.xml` to
   the `gh-pages` branch through the GitHub API.

If Apple rejects a submission, the script prints Apple's log of what was wrong
and stops. Nothing is published.

## How installed copies update

- The feed is `https://ephemerill.github.io/spider-buddy/appcast.xml` (GitHub
  Pages, from the `gh-pages` branch). It's baked into every shipped app as
  `SUFeedURL`, so **it must never move**. Pages serves changes within ~10 minutes.
- Sparkle checks once a day (or on **Check for Updates**), verifies the feed
  and `.dmg` against the EdDSA public key in `build.sh`, and installs.
- Copies older than 0.8.0 use their own updater, which downloads the release's
  first `.dmg`. Keep exactly **one** `.dmg` per release.

## Keys and credentials (all on this Mac)

| What | Where | Used for |
| --- | --- | --- |
| Developer ID Application: GABRIEL JONATHAN LOSH (86L5N846P4) | login keychain | Code signing. Expires 2027-02-01; renew it on developer.apple.com (Certificates) or in Xcode → Settings → Accounts. Builds already signed keep working. |
| `spider-notary` notarytool profile | login keychain | Notarization. Uses an app-specific password from account.apple.com. |
| Sparkle EdDSA private key | login keychain | Signing updates and the feed. **Losing it means installed copies can never update again.** Back it up with `build/Sparkle/bin/generate_keys -x <file>`. |
| GitHub token | git's osxkeychain credential | `gh` (passed as `GH_TOKEN`). |

Recreate the notary profile with:

```bash
xcrun notarytool store-credentials spider-notary \
  --apple-id gabrieljlosh@gmail.com --team-id 86L5N846P4
```

Sparkle lets you rotate the code-signing certificate or the EdDSA key, but not
both in the same release.

## Other commands

```bash
tools/release.sh --appcast       # after `gh release edit v<VERSION> --notes ...`:
                                 # rewrite and re-publish the appcast so the
                                 # update window shows the new notes
UNSIGNED=1 tools/release.sh      # ad-hoc signed, not notarized (as before 0.9)
SIGN_IDENTITY="..." tools/release.sh
NOTARY_PROFILE=other tools/release.sh
SPARKLE_KEY_FILE=key tools/release.sh   # use an exported EdDSA key instead of the keychain
```

## Notes

- Changing from ad-hoc signing to Developer ID (0.8.0 → 0.9.0) changes the
  app's signing identity, so users grant Screen Recording and Accessibility
  once more after that update.
- `./run.sh` / `./build.sh` (the `spiders.app` testing build) stay ad-hoc
  signed. Only releases are signed and notarized.
- Signing and notarizing use the keychain, so the script can't run inside a
  sandboxed shell.
