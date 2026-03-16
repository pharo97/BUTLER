# PRD-14: BUTLER — Code Signing & Notarization Plan

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering / DevOps

---

## 1. Overview

BUTLER distributes outside the Mac App Store. Every binary must be:
1. Signed with a Developer ID certificate (not an App Store distribution certificate)
2. Notarized by Apple's notarization service
3. Stapled (notarization ticket embedded in the artifact)

Without this, macOS Gatekeeper will block installation on any Mac with default security settings. There is no workaround acceptable for a production product — users should never need to right-click → Open or disable Gatekeeper.

---

## 2. Certificate Types Required

| Certificate | Purpose | Where Used |
|------------|---------|-----------|
| Developer ID Application | Sign .app bundles and embedded binaries | `Butler.app`, `butler-cli` binary |
| Developer ID Installer | Sign .pkg installer packages | If we ship a .pkg installer (optional) |

Both are issued by Apple via the Apple Developer portal. They require:
- Active Apple Developer Program membership ($99/year)
- Certificate Signing Request (CSR) generated on a Mac with secure access
- Private key stored in macOS Keychain on the build machine; backed up to encrypted storage

**Do NOT use:** App Store distribution certificates (will fail Gatekeeper for direct distribution).

---

## 3. Signing Entitlements

Two entitlements files are maintained. One per binary type.

### 3.1 Butler.app Entitlements (`Butler.entitlements`)

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Disable App Sandbox — required for Accessibility API and AppleScript -->
    <key>com.apple.security.app-sandbox</key>
    <false/>

    <!-- Hardened Runtime is REQUIRED for notarization — enable it -->
    <!-- Hardened Runtime exceptions needed for our use case: -->

    <!-- Allow JIT compilation (for Metal shaders) -->
    <key>com.apple.security.cs.allow-jit</key>
    <false/>

    <!-- Allow unsigned executable memory (needed by some frameworks — verify if needed) -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <false/>

    <!-- Allow dyld environment variables (should be false for production) -->
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <false/>

    <!-- Disable library validation for dynamic plugins (false = strict) -->
    <key>com.apple.security.cs.disable-library-validation</key>
    <false/>

    <!-- Required capabilities -->
    <key>com.apple.security.device.audio-input</key>
    <true/>

    <key>com.apple.security.personal-information.speech-recognition</key>
    <true/>

    <key>com.apple.security.automation.apple-events</key>
    <true/>

    <key>com.apple.security.files.downloads.read-write</key>
    <true/>

    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>

    <key>com.apple.security.personal-information.calendars</key>
    <true/>

    <!-- Network client — for Claude API calls -->
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

### 3.2 butler-cli Entitlements (`butler-cli.entitlements`)

The CLI binary is minimal. It only needs network access (none, it uses Unix socket) and no special system capabilities.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
    <!-- CLI does not use sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <false/>

    <!-- No special capabilities required -->
    <!-- The CLI communicates exclusively via Unix domain socket -->
</dict>
</plist>
```

### 3.3 Hardened Runtime Requirement

Notarization requires Hardened Runtime to be enabled on all signed binaries. This is set during signing via `-o runtime` flag.

Hardened Runtime restricts:
- Unsigned code injection
- DYLD environment variable overrides
- Unsigned library loading

These restrictions are acceptable for BUTLER. No third-party injection is used.

---

## 4. Signing Process

### 4.1 Sign All Binaries in App Bundle

Order matters: sign nested binaries before signing the parent app bundle.

```bash
SIGNING_IDENTITY="Developer ID Application: Company Name (TEAM_ID)"
APP_PATH="./build/Butler.app"

# Step 1: Sign all frameworks (if any)
find "$APP_PATH/Contents/Frameworks" -name "*.framework" -o -name "*.dylib" | \
    xargs -I {} codesign \
        --force \
        --sign "$SIGNING_IDENTITY" \
        --options runtime \
        --timestamp \
        {}

# Step 2: Sign the CLI binary (nested in .app/Contents/MacOS/)
codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "butler-cli.entitlements" \
    "$APP_PATH/Contents/MacOS/butler-cli"

# Step 3: Sign Metal shader library (if present)
codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    "$APP_PATH/Contents/Resources/default.metallib" 2>/dev/null || true

# Step 4: Sign the main app bundle last
codesign \
    --force \
    --sign "$SIGNING_IDENTITY" \
    --options runtime \
    --timestamp \
    --entitlements "Butler.entitlements" \
    "$APP_PATH"

# Step 5: Verify
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
spctl --assess --type execute --verbose "$APP_PATH"
```

Expected output of `spctl --assess`:
```
./build/Butler.app: accepted
source=Developer ID
```

### 4.2 Sign the DMG

The DMG must also be signed (not just its contents):

```bash
codesign \
    --sign "$SIGNING_IDENTITY" \
    --timestamp \
    "Butler-1.0.0.dmg"
```

---

## 5. Notarization Process

### 5.1 Notarization Workflow (Apple Notary Service)

```
Build + Sign
      │
      ▼
Submit to Apple Notary Service
      │ (xcrun notarytool submit)
      │
      ▼
Apple scans for malware,
checks signing, checks entitlements
      │
      ▼ (typically 1–5 minutes)
      │
  ┌───┴────────────────────────────┐
  │ APPROVED                       │ REJECTED
  ▼                                ▼
Staple ticket                 Read rejection log
to artifact                   Fix issues
      │                       Re-sign + re-submit
      ▼
Distribute
```

### 5.2 Submitting the DMG

```bash
xcrun notarytool submit "Butler-1.0.0.dmg" \
    --apple-id "developer@company.com" \
    --team-id "XXXXXXXXXX" \
    --password "@keychain:AC_PASSWORD" \
    --wait \
    --output-format json

# On success:
# {"status": "Accepted", "id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"}

# On failure — get detailed log:
xcrun notarytool log "SUBMISSION_ID" \
    --apple-id "developer@company.com" \
    --team-id "XXXXXXXXXX" \
    --password "@keychain:AC_PASSWORD"
```

### 5.3 Stapling the Notarization Ticket

```bash
xcrun stapler staple "Butler-1.0.0.dmg"
# Stapling ensures the artifact is notarized even offline (ticket embedded in file)

xcrun stapler validate "Butler-1.0.0.dmg"
# Should print: "The validate action worked!"
```

Also staple the .app itself (for cases where the app is distributed without the DMG):
```bash
xcrun stapler staple "Butler.app"
```

---

## 6. Common Notarization Rejection Causes & Fixes

| Rejection Reason | Cause | Fix |
|-----------------|-------|-----|
| Binary not signed with Hardened Runtime | Missing `-o runtime` in codesign | Add `--options runtime` to all sign commands |
| Invalid entitlements | Entitlement key typo or wrong value type | Validate entitlements plist with `plutil -lint` |
| Unsigned binary in bundle | Forgot to sign a nested binary | Run `codesign --verify --deep` first |
| Timestamp missing | Missing `--timestamp` flag | Add `--timestamp` to all codesign calls |
| Network call to non-https | App makes HTTP (not HTTPS) request | Enforce HTTPS for all network calls (ATS) |
| Third-party code injection | Framework with missing or invalid signature | Sign all third-party frameworks before signing app |
| JIT entitlement without hardware reason | Unnecessary JIT entitlement | Remove if Metal shaders don't require it |

---

## 7. CI/CD Integration

### 7.1 GitHub Actions Workflow

```yaml
name: Release

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  build-sign-notarize:
    runs-on: macos-15
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Install certificates
        env:
          BUILD_CERTIFICATE_BASE64: ${{ secrets.BUILD_CERTIFICATE_BASE64 }}
          P12_PASSWORD: ${{ secrets.P12_PASSWORD }}
          KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
        run: |
          # Create temporary keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security set-keychain-settings -lut 21600 build.keychain
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain

          # Import certificate
          echo "$BUILD_CERTIFICATE_BASE64" | base64 --decode > certificate.p12
          security import certificate.p12 -k build.keychain \
              -P "$P12_PASSWORD" -T /usr/bin/codesign
          security list-keychain -d user -s build.keychain
          security set-key-partition-list -S apple-tool:,apple: \
              -s -k "$KEYCHAIN_PASSWORD" build.keychain

      - name: Build
        run: |
          xcodebuild archive \
              -scheme Butler \
              -archivePath ./build/Butler.xcarchive \
              -destination "generic/platform=macOS"

      - name: Export and sign
        env:
          TEAM_ID: ${{ secrets.TEAM_ID }}
        run: |
          xcodebuild -exportArchive \
              -archivePath ./build/Butler.xcarchive \
              -exportOptionsPlist ExportOptions.plist \
              -exportPath ./build/

          # Additional signing steps for butler-cli
          codesign --force --sign "Developer ID Application: $TEAM_ID" \
              --options runtime --timestamp \
              --entitlements butler-cli.entitlements \
              ./build/Butler.app/Contents/MacOS/butler-cli

      - name: Create DMG
        run: |
          brew install create-dmg
          create-dmg \
              --volname "Butler" \
              --background "assets/dmg-background.png" \
              --window-size 600 400 \
              --icon-size 128 \
              --icon "Butler.app" 170 180 \
              --app-drop-link 430 180 \
              "Butler-${{ github.ref_name }}.dmg" \
              "./build/Butler.app"

          codesign --sign "Developer ID Application: ${{ secrets.TEAM_ID }}" \
              --timestamp "Butler-${{ github.ref_name }}.dmg"

      - name: Notarize
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          TEAM_ID: ${{ secrets.TEAM_ID }}
          APP_SPECIFIC_PASSWORD: ${{ secrets.APP_SPECIFIC_PASSWORD }}
        run: |
          xcrun notarytool submit "Butler-${{ github.ref_name }}.dmg" \
              --apple-id "$APPLE_ID" \
              --team-id "$TEAM_ID" \
              --password "$APP_SPECIFIC_PASSWORD" \
              --wait

          xcrun stapler staple "Butler-${{ github.ref_name }}.dmg"

      - name: Upload release artifact
        uses: actions/upload-artifact@v4
        with:
          name: Butler-release
          path: "Butler-${{ github.ref_name }}.dmg"

      - name: Create GitHub release
        uses: softprops/action-gh-release@v2
        with:
          files: "Butler-${{ github.ref_name }}.dmg"
```

### 7.2 Required CI Secrets

| Secret | Description |
|--------|-------------|
| `BUILD_CERTIFICATE_BASE64` | Developer ID Application cert + private key as base64 .p12 |
| `P12_PASSWORD` | Password for the .p12 file |
| `KEYCHAIN_PASSWORD` | Temporary keychain password (random, per-run) |
| `TEAM_ID` | Apple Developer Team ID |
| `APPLE_ID` | Apple ID email for notarization |
| `APP_SPECIFIC_PASSWORD` | App-specific password for notarization (generated at appleid.apple.com) |
| `SPARKLE_PRIVATE_KEY` | EdDSA private key for Sparkle update signing |

**Certificate storage:** The .p12 file is stored as a base64-encoded repository secret. The private key is NEVER committed to version control.

---

## 8. Sparkle Update Signing

Sparkle 2 uses EdDSA (Ed25519) for update package verification.

```bash
# Generate key pair (one-time — store private key in secrets manager)
./bin/generate_keys  # Sparkle utility

# Sign the update DMG
./bin/sign_update "Butler-1.1.0.dmg" --ed-key-file sparkle_private.pem
# Output: EdDSA signature string → paste into appcast XML <enclosure sparkle:edSignature="...">

# Public key → embed in Info.plist:
# <key>SUPublicEDKey</key>
# <string>BASE64_PUBLIC_KEY</string>
```

---

## 9. Certificate Renewal

Developer ID certificates expire after 5 years from issuance. However:
- **Code signed artifacts are valid indefinitely** if they include a trusted timestamp at signing time (which `--timestamp` provides)
- **Certificate renewal** is needed only for signing NEW builds after expiry
- **Re-notarization** of existing artifacts is not required

**Renewal process:**
1. Generate new CSR from build machine
2. Request new Developer ID Application certificate from Apple Developer portal
3. Download and import to build machine Keychain
4. Update `BUILD_CERTIFICATE_BASE64` in CI secrets
5. No change to existing distributed artifacts required

**Calendar reminder:** Set renewal reminder for 60 days before expiry (5 years minus 60 days from initial issuance).

---

## 10. Gatekeeper Behavior for Users

When a user downloads BUTLER:

**First launch (notarized + stapled):**
```
macOS Gatekeeper check:
  ✓ Developer ID certificate valid
  ✓ Notarized by Apple
  ✓ Ticket stapled
  ✓ No known malware

Result: App opens without any dialog.
```

**First launch (notarized but not stapled, online):**
```
macOS Gatekeeper check:
  ✓ Certificate valid
  → Checks Apple's online notarization database
  ✓ Notarization confirmed
  ✓ No malware

Result: App opens. Dialog-free if certificate is trusted.
```

**First launch (not notarized — should never happen in production):**
```
Dialog: "Butler.app cannot be opened because it is from an unidentified developer."
```
This case should NEVER occur in a production release. All CI builds are notarized before publishing.
