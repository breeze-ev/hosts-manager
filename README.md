# Hosts Manager

Hosts Manager is a macOS app for managing `/etc/hosts` with profiles, structured list editing, source editing, real-time apply, automatic backups, and a signed background writer helper.

It is currently open source but has not published a signed DMG yet. You can build and run it locally with Xcode, or wait for the first Developer ID-signed release.

![Hosts Manager](website/assets/hosts-manager-main.png)

## Features

- Profile-based hosts management with one-click switching
- Structured list editing and raw `/etc/hosts` source editing
- Conflict and duplicate detection before writes
- Real-time apply when enabled profiles change
- Automatic timestamped backups with restore
- Optional silent writes through a privileged LaunchDaemon helper
- Chinese and English interface
- No telemetry, no network access, no third-party analytics

## Requirements

- macOS 26 or newer
- Xcode 26.6 or newer to build

## Build from Source

```bash
git clone https://github.com/breeze-ev/hosts-manager.git
cd hosts-manager
open hosts-manager.xcodeproj
```

Select your own development team in the Signing & Capabilities pane for both the `hosts-manager` and `HostsManagerHelper` targets. The app and helper must be signed by the same team so the helper can verify the caller.

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

`scripts/build-dmg.sh` archives, signs, notarizes, and staples a universal DMG. It is intended for maintainers with a Developer ID identity and the `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, and `APPLE_API_KEY_PATH` environment variables.

```bash
./scripts/build-dmg.sh --team-id YOUR_TEAM_ID --version 0.1.0
```

## Documentation

- [简体中文说明](README.zh-CN.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)
- [Privacy](PRIVACY.md)

## License

Hosts Manager is released under the [MIT License](LICENSE).
