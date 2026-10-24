# Privacy

Hosts Manager is designed to work entirely on your Mac.

## Data Access

- The app reads and writes `/etc/hosts`.
- The app stores profiles, settings, and backup records locally in Application Support using Core Data.
- Backup files are stored in Application Support and are never uploaded.

## Network and Telemetry

- The app makes no network requests.
- The app does not collect usage telemetry.
- The app does not include third-party analytics or advertising SDKs.

## Permissions

The background writer helper is a LaunchDaemon embedded in the app bundle. It is installed through the system Login Items approval flow and is only registered when you enable it in Settings. The helper accepts writes only from a Hosts Manager app signed by the same team.
