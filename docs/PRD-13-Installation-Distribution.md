# PRD-13: BUTLER — Installation & Distribution Strategy

**Version:** 1.0
**Date:** 2026-03-03
**Status:** Draft
**Owner:** Engineering / DevOps

---

## 1. Distribution Channels

BUTLER is distributed outside the Mac App Store. Three installation paths are supported:

| Method | Target User | CLI Included | GUI Included | Maintenance |
|--------|------------|-------------|-------------|-------------|
| DMG drag-and-drop | General user | Installed via post-install script | Yes | Sparkle auto-update |
| Terminal installer | Developer / advanced | Yes | Yes | Sparkle + manual |
| Homebrew CLI only | Power user | Yes | No (separate download) | `brew upgrade butler` |
| Homebrew Cask | Advanced user | Via post-install | Yes | `brew upgrade --cask butler` |

---

## 2. DMG Distribution

### 2.1 DMG Contents

```
Butler-1.0.0-arm64.dmg
└── [mounted volume: Butler]
    ├── Butler.app             ← Drag to Applications
    ├── Applications →         ← Alias to /Applications
    └── README.pdf             ← Quick start guide
```

DMG spec:
- Format: UDZO (zlib compressed)
- Background: custom branded image (1024×768)
- Window size: 600×400
- Icon arrangement: app icon left, Applications alias right
- Code signed: Yes (Developer ID Application)
- Notarized: Yes
- Stapled: Yes (stapled ticket embedded in DMG)

### 2.2 Post-Install CLI Setup

After dragging Butler.app to Applications, first launch triggers CLI setup:

```
Butler first launch — would you like to install the command-line interface?

  This adds 'butler' to /usr/local/bin so you can control Butler
  from the terminal.

  [Install CLI]    [Skip]    [Learn more]
```

If "Install CLI" is selected:
1. BUTLER.app creates symlink: `/usr/local/bin/butler → /Applications/Butler.app/Contents/MacOS/butler-cli`
2. Writes shell completions to `~/.butler/completions/`
3. Adds completion source to `~/.zshrc` or `~/.bash_profile` (with comment markers)
4. Runs `butler install` (creates `~/.butler/` structure, registers launchd agent)

If `/usr/local/bin` is not writable (no admin rights):
- Offer to install to `~/bin/butler` instead
- Advise user to add `~/bin` to `$PATH`

### 2.3 DMG Build Process

```bash
# Build and sign the app
xcodebuild archive -scheme Butler -archivePath ./build/Butler.xcarchive
xcodebuild -exportArchive \
    -archivePath ./build/Butler.xcarchive \
    -exportOptionsPlist ExportOptions.plist \
    -exportPath ./build/

# Create DMG using create-dmg
create-dmg \
    --volname "Butler" \
    --background "assets/dmg-background.png" \
    --window-size 600 400 \
    --icon-size 128 \
    --icon "Butler.app" 170 180 \
    --app-drop-link 430 180 \
    --codesign "$DEVELOPER_ID" \
    "Butler-$VERSION-arm64.dmg" \
    "build/Butler.app"

# Notarize the DMG
xcrun notarytool submit "Butler-$VERSION-arm64.dmg" \
    --apple-id "$APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$APP_SPECIFIC_PASSWORD" \
    --wait

# Staple notarization ticket to DMG
xcrun stapler staple "Butler-$VERSION-arm64.dmg"
```

### 2.4 Update via Sparkle

BUTLER.app includes [Sparkle 2](https://sparkle-project.org/) for in-app updates.

**Appcast URL:** `https://butlerapp.com/appcast.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Butler Updates</title>
        <item>
            <title>Version 1.1.0</title>
            <sparkle:version>42</sparkle:version>
            <sparkle:shortVersionString>1.1.0</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <sparkle:releaseNotesLink>https://butlerapp.com/releases/1.1.0</sparkle:releaseNotesLink>
            <enclosure
                url="https://cdn.butlerapp.com/releases/Butler-1.1.0-arm64.dmg"
                sparkle:edSignature="XXXXXXXX"
                length="25600000"
                type="application/octet-stream"/>
        </item>
    </channel>
</rss>
```

Sparkle checks for updates:
- On app launch (if >24h since last check)
- On explicit `butler update` CLI call
- User-configurable: daily / weekly / manually

Sparkle update is verified via EdDSA signature. The public key is embedded in Info.plist. Private key is stored in CI secrets only.

---

## 3. Terminal Installer

For users who prefer shell-based installation. A bash script hosted at `https://install.butlerapp.com`.

### 3.1 Usage

```bash
# One-liner
curl -fsSL https://install.butlerapp.com | bash

# With options
curl -fsSL https://install.butlerapp.com | bash -s -- --dir ~/Applications --no-launchagent
```

### 3.2 Installer Script Logic

```bash
#!/usr/bin/env bash
# butler-install.sh — BUTLER macOS installer
set -euo pipefail

BUTLER_VERSION="1.0.0"
INSTALL_DIR="${BUTLER_INSTALL_DIR:-/Applications}"
CLI_DIR="${BUTLER_CLI_DIR:-/usr/local/bin}"
NO_LAUNCHAGENT="${NO_LAUNCHAGENT:-false}"

# Detect architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    DMG_URL="https://cdn.butlerapp.com/releases/Butler-${BUTLER_VERSION}-arm64.dmg"
    DMG_SHA256="[sha256]"
else
    DMG_URL="https://cdn.butlerapp.com/releases/Butler-${BUTLER_VERSION}-x86_64.dmg"
    DMG_SHA256="[sha256]"
fi

# Verify macOS version
MACOS_VERSION=$(sw_vers -productVersion)
MAJOR=$(echo $MACOS_VERSION | cut -d. -f1)
if [[ $MAJOR -lt 14 ]]; then
    echo "Error: Butler requires macOS 14 (Sonoma) or later. Current: $MACOS_VERSION"
    exit 1
fi

echo "Installing Butler $BUTLER_VERSION..."
echo "Architecture: $ARCH | macOS: $MACOS_VERSION"
echo ""

# Download DMG
TMPDIR=$(mktemp -d)
DMG_PATH="$TMPDIR/Butler-$BUTLER_VERSION.dmg"
echo "Downloading..."
curl -fL --progress-bar "$DMG_URL" -o "$DMG_PATH"

# Verify checksum
COMPUTED=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
if [[ "$COMPUTED" != "$DMG_SHA256" ]]; then
    echo "Error: Checksum mismatch. Download may be corrupted."
    rm -rf "$TMPDIR"
    exit 1
fi

# Verify signature (Gatekeeper check)
spctl --assess --type execute "$DMG_PATH" 2>/dev/null || {
    echo "Error: DMG signature verification failed."
    rm -rf "$TMPDIR"
    exit 1
}

# Mount DMG
MOUNT_POINT=$(hdiutil attach "$DMG_PATH" -nobrowse -quiet | tail -1 | awk '{print $3}')
trap "hdiutil detach '$MOUNT_POINT' -quiet 2>/dev/null; rm -rf '$TMPDIR'" EXIT

# Copy app
echo "Installing to $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR/Butler.app" ]]; then
    echo "Existing installation found. Replacing..."
    rm -rf "$INSTALL_DIR/Butler.app"
fi
cp -R "$MOUNT_POINT/Butler.app" "$INSTALL_DIR/"

# Install CLI symlink
if [[ -w "$CLI_DIR" ]]; then
    ln -sf "$INSTALL_DIR/Butler.app/Contents/MacOS/butler-cli" "$CLI_DIR/butler"
    echo "CLI installed: $CLI_DIR/butler"
else
    echo "Note: $CLI_DIR is not writable. Skipping CLI symlink."
    echo "      To install manually: sudo ln -sf $INSTALL_DIR/Butler.app/Contents/MacOS/butler-cli /usr/local/bin/butler"
fi

# Initialize Butler
"$INSTALL_DIR/Butler.app/Contents/MacOS/butler-cli" install --no-launch-agent-prompt "$([[ $NO_LAUNCHAGENT == "true" ]] && echo '--no-launch-agent' || echo '')"

echo ""
echo "✓ Butler $BUTLER_VERSION installed successfully."
echo "  App:    $INSTALL_DIR/Butler.app"
echo "  CLI:    $CLI_DIR/butler"
echo "  Config: ~/.butler/"
echo ""
echo "  Run 'butler status' to verify."
echo "  Open Butler.app or run 'open -a Butler' to start."
```

### 3.3 Installer Security
- Downloaded over HTTPS only
- SHA-256 checksum verified before mounting
- `spctl --assess` verifies Developer ID signature before installation
- Installer script itself is served over HTTPS with SHA-256 listed on download page
- Does not execute arbitrary code from the internet beyond the signed DMG

---

## 4. Homebrew Distribution

Two Homebrew formulas:

### 4.1 Homebrew CLI Formula (`butler`)

Distributed via a custom tap: `butler-app/tap`

```
brew tap butler-app/tap
brew install butler
```

Installs the `butler-cli` binary only. The CLI can operate against a separately installed BUTLER.app.

Formula maintained at: `github.com/butler-app/homebrew-tap`

See PRD-12 for full formula source.

### 4.2 Homebrew Cask (`butler`)

Installs the full .app via Homebrew Cask. Requires submission to `homebrew/cask` (or served from custom tap).

```ruby
cask "butler" do
  version "1.0.0"
  sha256 "..."

  url "https://cdn.butlerapp.com/releases/Butler-#{version}-arm64.dmg",
      verified: "cdn.butlerapp.com/releases/"

  name "Butler"
  desc "AI operating companion for macOS"
  homepage "https://butlerapp.com"

  depends_on macos: ">= :sonoma"

  app "Butler.app"
  binary "#{appdir}/Butler.app/Contents/MacOS/butler-cli", target: "butler"

  postflight do
    system_command "#{appdir}/Butler.app/Contents/MacOS/butler-cli",
                   args: ["install", "--no-launch-agent-prompt"]
  end

  uninstall quit:       "com.butler.app",
            delete:     "#{appdir}/Butler.app"

  zap trash: [
    "~/.butler",
    "~/Library/Application Support/Butler",
    "~/Library/Caches/com.butler.app",
    "~/Library/Logs/Butler",
    "~/Library/Preferences/com.butler.app.plist",
  ]
end
```

---

## 5. LaunchAgent Registration

BUTLER registers as a LaunchAgent to start automatically at login (optional during installation).

**Plist location:** `~/Library/LaunchAgents/com.butler.app.plist`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.butler.app</string>

    <key>ProgramArguments</key>
    <array>
        <string>/Applications/Butler.app/Contents/MacOS/Butler</string>
        <string>--background</string>
    </array>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <false/>

    <key>ProcessType</key>
    <string>Interactive</string>

    <key>StandardOutPath</key>
    <string>/tmp/butler.stdout</string>

    <key>StandardErrorPath</key>
    <string>/tmp/butler.stderr</string>
</dict>
</plist>
```

**Registration:**
```bash
launchctl load ~/Library/LaunchAgents/com.butler.app.plist
```

**Deregistration (uninstall):**
```bash
launchctl unload ~/Library/LaunchAgents/com.butler.app.plist
rm ~/Library/LaunchAgents/com.butler.app.plist
```

---

## 6. Update Mechanisms by Channel

| Channel | Update Method | User Notification | Rollback Support |
|---------|--------------|-------------------|-----------------|
| DMG direct | Sparkle in-app updater | In-app banner + Glass Chamber | Keep previous .app in Trash |
| Terminal installer | `butler update` CLI command | CLI output | Manual |
| Homebrew CLI | `brew upgrade butler` | None (manual) | `brew switch butler 1.0.0` |
| Homebrew Cask | `brew upgrade --cask butler` | None (manual) | `brew reinstall butler@1.0.0` |

### 6.1 Sparkle Update Flow

```
App launch
│
├── Check: last_update_check > 24h ago?
│   YES → query appcast URL
│         verify appcast signature
│         compare version to running build
│
│         version available?
│         YES → show Glass Chamber notification:
│                 "Butler 1.1.0 is available. Update now?"
│                 [Update]  [Later]  [Release Notes]
│
│         [Update] selected
│         ├── Sparkle downloads update package
│         ├── Verifies EdDSA signature against embedded public key
│         ├── Extracts to temp location
│         ├── Quits BUTLER.app
│         ├── Replaces Butler.app bundle
│         └── Relaunches Butler.app
│
└── Update complete
```

---

## 7. File System Footprint

```
Installation:
  /Applications/Butler.app              ~45 MB (app bundle)
  /usr/local/bin/butler                 symlink only

Runtime (user):
  ~/.butler/config.json                 ~2 KB
  ~/.butler/run/butler.sock             runtime only
  ~/.butler/run/.auth                   runtime only
  ~/.butler/data/butler.db              2–50 MB (grows with use)
  ~/.butler/logs/butler.log             max 10 MB (rotated)
  ~/.butler/completions/                ~15 KB
  ~/Library/LaunchAgents/com.butler.app.plist   ~1 KB

System (optional):
  ~/Library/Caches/com.butler.app/      <5 MB
  ~/Library/Preferences/com.butler.app.plist    ~1 KB

Total disk footprint (installed):  ~50–100 MB
```

---

## 8. Uninstallation

Full uninstall removes all of the above. `butler uninstall` handles:
1. `launchctl unload ~/Library/LaunchAgents/com.butler.app.plist`
2. `rm ~/Library/LaunchAgents/com.butler.app.plist`
3. Remove `/usr/local/bin/butler` symlink
4. Remove `~/.butler/` (unless `--keep-data`)
5. Remove `~/Library/Caches/com.butler.app/`
6. Remove `~/Library/Preferences/com.butler.app.plist`
7. Remove `/Applications/Butler.app`

For Homebrew Cask installs, the `zap` section in the cask formula handles the same cleanup.

---

## 9. Intel vs Apple Silicon

BUTLER ships as a universal binary where possible, or separate architecture-specific DMGs.

| Artifact | Strategy |
|----------|---------|
| BUTLER.app | Universal binary (arm64 + x86_64 in single bundle) |
| butler-cli | Universal binary |
| DMG | Single universal DMG (labeled `Butler-1.0.0.dmg`) |
| Homebrew | Homebrew handles architecture automatically via `url` block |

Metal shaders: arm64 and x86_64 variants compiled into universal binary. Shader source compiled to `.metallib` at build time — not JIT compiled at runtime.

---

## 10. Version Numbering

Format: `MAJOR.MINOR.PATCH`

| Component | Increment trigger |
|-----------|------------------|
| MAJOR | Breaking changes to CLI API, IPC protocol, config schema, or data format |
| MINOR | New features (new commands, new modules, new animation states) |
| PATCH | Bug fixes, performance improvements, no new features |

Build number (monotonically increasing integer) is used by Sparkle for update comparison. CFBundleVersion = build number. CFBundleShortVersionString = `MAJOR.MINOR.PATCH`.

Pre-release suffixes: `1.1.0-beta.1`, `1.1.0-rc.1`
