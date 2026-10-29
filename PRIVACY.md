# Privacy

Hosts Manager is designed to keep your data on your Mac.

## Data Access

- The app reads and writes `/etc/hosts`.
- The app stores profiles, settings, and backup records locally in Application Support using Core Data.
- Backup files are stored in Application Support and are never uploaded.

## Network and Telemetry

- The bundled Sparkle updater checks a signed appcast automatically at most once every 24 hours, and when you choose **Check for Updates** from the app menu or Settings.
- The appcast is served from the public repository through `raw.githubusercontent.com`. If an update is available and you choose to install it, Sparkle downloads the architecture-specific DMG from GitHub Releases and verifies the signed feed and update with EdDSA. macOS may additionally apply Gatekeeper checks to the downloaded app.
- These requests necessarily disclose standard network information, such as your IP address, to GitHub. GitHub's own privacy terms apply. Profiles, hosts content, backups, and settings are never included in update requests.
- The app does not collect usage telemetry.
- The app does not include third-party analytics or advertising SDKs.

## Permissions

The background writer helper is a LaunchDaemon embedded in the app bundle. It is installed through the system Login Items approval flow and is only registered when you enable it in Settings. The helper accepts writes only from a Hosts Manager app signed by the same team.
