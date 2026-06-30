---
summary: "PDTBar release checklist for GitHub assets, notarized app archives, and Homebrew cask distribution."
read_when:
  - Starting a PDTBar release
  - Updating signing/notarization setup
  - Updating Homebrew distribution
---

# Release Checklist

PDTBar ships through GitHub Releases. Homebrew cask distribution uses the versioned app archive:

```bash
PDTBar-macos-universal-<version>.zip
```

The archive must contain `PDTBar.app` at the zip root.

## Required GitHub Secrets

Public cask releases require Developer ID signing, notarization, and stapling before the app zip is uploaded. Configure these repository secrets before publishing a public release:

- `PDTBAR_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`.
- `PDTBAR_DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD`: password for that `.p12`.
- `PDTBAR_RELEASE_KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `PDTBAR_APP_IDENTITY`: exact Developer ID Application identity name from `security find-identity`.
- `APP_STORE_CONNECT_API_KEY_P8`: App Store Connect API key contents.
- `APP_STORE_CONNECT_KEY_ID`: App Store Connect key id.
- `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect issuer id.
- `HOMEBREW_TAP_TOKEN`: token allowed to run `BramVR/homebrew-tap` workflows.

The release workflow sets `PDTBAR_REQUIRE_NOTARIZATION=1` on release events. If any signing/notary secret is missing, the release app archive job fails before upload.

## Manual Archive Proof

Manual workflow runs can build an unsigned proof archive without publishing:

```bash
gh workflow run release-cli.yml -f tag=v0.0.0-test
```

Local proof for the current Mac architecture:

```bash
ARCHES="$(uname -m)" ./Scripts/package_release_app.sh v0.0.0-test
ditto -x -k .build/release-artifacts/PDTBar-macos-$(uname -m)-0.0.0-test.zip /tmp/pdtbar-release-proof
codesign --verify --deep --strict --verbose=2 /tmp/pdtbar-release-proof/PDTBar.app
```

## Publish Flow

1. Finalize release notes in the GitHub release body.
2. Publish tag/release `v<version>`.
3. Wait for `.github/workflows/release-cli.yml`.
4. Confirm release assets exist:
   - `PDTBar-macos-universal-<version>.zip`
   - `PDTBar-macos-universal-<version>.zip.sha256`
   - `pdtbar-v<version>-macos-arm64.tar.gz`
   - `pdtbar-v<version>-macos-x86_64.tar.gz`
5. Download the app zip and verify:

```bash
ditto -x -k PDTBar-macos-universal-<version>.zip /tmp/pdtbar-release
codesign --verify --deep --strict --verbose=2 /tmp/pdtbar-release/PDTBar.app
spctl --assess --type execute --verbose /tmp/pdtbar-release/PDTBar.app
xcrun stapler validate /tmp/pdtbar-release/PDTBar.app
```

## Homebrew Cask

The release workflow dispatches `BramVR/homebrew-tap` `update-cask.yml` after the app archive uploads. That workflow renders `Casks/pdtbar.rb` with:

- URL `https://github.com/BramVR/pdtbar/releases/download/v<version>/PDTBar-macos-universal-<version>.zip`
- SHA-256 of the app archive
- `depends_on macos: :sonoma`
- `app "PDTBar.app"`

If dispatch fails, manually update the tap from a clean `BramVR/homebrew-tap` checkout:

```bash
python3 .github/scripts/update_cask.py \
  --cask pdtbar \
  --tag v<version> \
  --repository BramVR/pdtbar \
  --artifact-template 'PDTBar-macos-universal-{version}.zip'
```

Then commit and push the changed `Casks/pdtbar.rb`.

## Homebrew Proof

After the tap commit lands:

```bash
brew update
brew uninstall --cask pdtbar || true
brew install --cask BramVR/tap/pdtbar
open -a PDTBar
brew uninstall --cask pdtbar
```

Upgrade proof needs two published versions:

```bash
brew install --cask BramVR/tap/pdtbar
brew update
brew upgrade --cask BramVR/tap/pdtbar
```

Homebrew owns updates for cask installs. PDTBar does not ship Sparkle or another in-app updater in this slice.
