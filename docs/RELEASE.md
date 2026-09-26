# Release guide

## Local unsigned test build

```zsh
./Scripts/build-app.sh
./Scripts/create-release.sh 0.1.0
```

This creates a universal ZIP and a DMG installer in `dist/`, each with a
`.sha256` file beside it. The DMG contains the app plus an `Applications`
shortcut for drag-and-drop installation. Both are valid GitHub downloads. macOS
can show a one-time Gatekeeper warning because the app is not associated with an
identified Apple developer; users who trust the source can choose Finder's
**Open** command or allow it in System Settings.

## Checksums are mandatory

The release workflow uploads the `.sha256` files along with the downloads, and
the in-app updater refuses to install a release whose ZIP has no published
digest — it offers a manual download instead. A release published without those
assets therefore reaches existing users as a notification only. Verify a
download by hand with:

```zsh
shasum -c LimitChecker-<version>-macos-universal.zip.sha256
```

## Developer-ID signing and notarization

For public downloads, enroll in the Apple Developer Program and use a
`Developer ID Application` certificate. Set its keychain identity before the
build:

```zsh
export CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
./Scripts/create-release.sh 0.1.0
```

Create a ZIP with `ditto -c -k --keepParent`, submit that ZIP with `xcrun
notarytool submit`, wait for acceptance, staple the ticket with `xcrun stapler
staple`, and then create the final download ZIP.

## GitHub Actions secrets

The release workflow supports these optional secrets:

- `APPLE_CERTIFICATE_BASE64`: Developer-ID `.p12`, base64 encoded
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_KEYCHAIN_PASSWORD`
- `APPLE_SIGNING_IDENTITY`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_PASSWORD`

When all signing and notarization secrets are present, a version tag creates a
notarized GitHub Release with a universal ZIP and DMG. Without them, the same
tag creates an ad-hoc-signed GitHub Release and clearly labels it as not
notarized.
