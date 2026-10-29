<p align="center">
<img height="256" src="website/assets/hosts-manager-icon.png">
</p>

<h1 align="center">Hosts Manager</h1>

<p align="center">Hosts Manager is the <b>modern</b> hosts file manager for macOS.</p>

Hosts Manager manages the domain-to-IP mappings in `/etc/hosts`, serving two main purposes: local domain mapping for front-end/back-end development, and blocking network connections of specific apps or domains.

- **Project-based profiles**: organize mappings in profiles that can be switched or combined per project or scenario, and easily shared with teammates.
- **Two editing styles**: structured list editing and raw hosts source editing — pick whichever suits your habit.
- **Backup on every write**: every change is automatically backed up to prevent accidental loss, and profiles can be imported and exported.

## Screenshot

<p align="center">
<img src="website/assets/hosts-manager-main.png" alt="Hosts Manager main window">
</p>

## Features

- Profile-based hosts management with one-click switching
- Combinable management: enable multiple profiles and merge them into one write
- Import and export profiles
- Native Swift (SwiftUI + Swift)
- Structured list editing and raw `/etc/hosts` source editing
- Conflict and duplicate detection before writes
- Automatic merging that preserves entries added through other tools
- Real-time apply when enabled profiles change
- Automatic timestamped backups with restore
- Optional silent writes through a privileged LaunchDaemon helper
- Daily stable-release update checks through Sparkle's standard update window, with EdDSA verification, in-place installation, and relaunch
- Chinese and English interface
- No telemetry or third-party analytics; Sparkle contacts only the signed appcast and GitHub Releases for updates

## Requirements

- macOS 26 or newer
- Xcode 26.6 or newer to build

## Installation

Download the DMG matching your Mac from the [Releases](https://github.com/breeze-ev/hosts-manager/releases) page:

| File | Mac |
| --- | --- |
| `Hosts-Manager-*-arm64.dmg` | Apple Silicon (M-series) |
| `Hosts-Manager-*-x86_64.dmg` | Intel |

Not sure which one? Open the Apple menu → About This Mac: "Chip" shows an Apple M-series for arm64, or Intel for x86_64.

To install:

1. Open the downloaded DMG.
2. Drag **Hosts Manager** into the **Applications** folder.
3. Launch Hosts Manager from Applications.

Open-source releases do not currently require the paid Apple Developer Program. They are signed with a free Apple Development certificate and are not notarized by Apple. If Gatekeeper blocks the first launch, open **System Settings → Privacy & Security** and choose **Open Anyway** next to the warning. Do not use an ad-hoc build because its background writer helper cannot complete system registration.

## Build from Source

```bash
git clone https://github.com/breeze-ev/hosts-manager.git
cd hosts-manager
open hosts-manager.xcodeproj
```

Select your own development team in the Signing & Capabilities pane for both the `hosts-manager` and `HostsManagerHelper` targets. The app and helper must be signed by the same team so the helper can verify the caller.

Xcode resolves and pins `Sparkle 2.9.6` through Swift Package Manager; no manual dependency installation is required.

You can also build from the command line:

```bash
xcodebuild build \
  -project hosts-manager.xcodeproj \
  -scheme hosts-manager \
  -destination 'platform=macOS' \
  -derivedDataPath build
```

## Using the App

On first launch, Hosts Manager creates a read-only System profile and an editable default profile. Enable the background writer helper in Settings to write `/etc/hosts` silently. The app backs up the current file before every write and stores backups in Application Support.

For a source-only build, the helper may not install unless both the app and helper are properly signed with your own team.

## Release Packaging

`scripts/build-dmg.sh` archives, signs, and builds two separate DMGs (arm64 and x86_64). Version, build number, and Team ID are read from the Xcode project automatically:

```bash
./scripts/build-dmg.sh           # Developer ID signed + notarized (requires a paid developer certificate)
./scripts/build-dmg.sh --dev     # free Apple Development signing, no notarization; helper works (recommended without a paid account)
./scripts/build-dmg.sh --adhoc   # ad-hoc signed, no notarization, no certificate needed (note: the background helper won't work, see below)
```

Only Developer ID distribution needs `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, and `APPLE_API_KEY_PATH` for notarization. Without a paid developer account, use `--dev`; it does not need an Apple API key, issuer ID, or notarization credentials. Artifacts are written to `dist/` with sha256 checksum files.

Without a paid developer account, publish from the maintainer's Mac. Install GitHub CLI and pandoc, then sign in:

```bash
brew install gh pandoc
gh auth login
```

After confirming that the Keychain contains a valid **Apple Development** identity and the Sparkle private key, run:

```bash
./scripts/release-local.sh --version 1.0.1 --build-number 20
```

The script builds both architectures with `--dev`, renders white-background HTML release notes from `CHANGELOG.md`, signs both Sparkle appcasts, creates the GitHub Release, and commits and pushes the updated feeds. Only `SUPublicEDKey` is stored in the repository; the Sparkle private key stays in the maintainer's Keychain, and the current release flow does not need a `SPARKLE_PRIVATE_KEY` GitHub secret. To initialize the key locally:

```bash
/path/to/Sparkle/bin/generate_keys --account personal.hosts-manager
```

GitHub-hosted Actions runners cannot access your free personal development certificate, so do not publish ad-hoc DMGs there: the background writer helper will not work. `scripts/generate-appcast.sh` can also update an appcast manually. The signed feeds live in `Sparkle/` and are also uploaded as GitHub Release assets; the app selects the stable Raw feed for its current architecture.

> **Signing matters**: the background writer helper is registered via SMAppService, and macOS ties Login Items approval to the code-signing identity. Ad-hoc builds have no stable identity, so the toggle can be switched on but the daemon never actually registers. Without a paid account, use `--dev` (a free Apple Development certificate) and tell users to approve the app under Privacy & Security on first launch. Frictionless distribution to a broad audience still requires the paid Developer ID program and Apple notarization.

## Documentation

- [中文说明](README.md)
- [Changelog](CHANGELOG.en.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Privacy](PRIVACY.md)
- [Third-party notices](hosts-manager/ThirdPartyNotices.txt)

## License

Hosts Manager is released under the [MIT License](LICENSE).
