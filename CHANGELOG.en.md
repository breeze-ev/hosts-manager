# Changelog

[中文](CHANGELOG.md)

## 1.0.1 - 2026-10-29

### Added

- Added an optional main-window background blur, enabled by default. It can be disabled with the **Background blur** switch in Settings to use a solid window background instead.

### Changed

- Update checks now use Sparkle 2.9.6's standard update window: daily signed-appcast checks, a manual flow with release notes, download progress and **Install Update**, followed by in-place replacement and relaunch. The custom GitHub API, token, SHA-256 download and DMG mounting flow has been removed.

### Improved

- Valid entries added to `/etc/hosts` by external tools are preserved and merged automatically on the next write. The reconciliation prompt no longer blocks profile changes, while hostnames managed by a profile still use the app's value and identical IP/hostname mappings are deduplicated.
- Failed profile-state saves still pause further writes and provide a recovery path, preventing the file and profile switches from diverging silently.
- Release packaging now supports free Apple Development certificates: `--dev` keeps the background helper working without a paid developer account, and `scripts/release-local.sh` signs appcasts and creates the GitHub Release locally. Ad-hoc builds are no longer used for public releases.

## 1.0.0 - 2026-10-27

First stable release.

### Added

- In-app update center: check GitHub stable releases from the menu (`Check for Updates…`, ⇧⌘U) or Settings, with automatic checks at most once per day. Downloads the DMG for Apple Silicon / Intel, shows progress, supports cancellation, verifies SHA-256 when available, reveals the installer in Finder, and opens it after applying quarantine metadata. The releases page remains available as a fallback.
- Import hosts profiles from files: accepts `.hosts` or plain text, imports user entries as an unapplied profile, enforces a 1 MiB limit, and reports invalid encodings, invalid content, and files without importable user entries.
- `/etc/hosts` reconciliation protection: compares the system file with the applied profile selection on launch and before writes. External edits or failed state commits block further overwrites and offer “Keep System File” or “Reapply Profiles”.
- Source draft management: preserves unapplied drafts, detects conflicts between list and source edits, supports “Discard”, and avoids rewriting a profile when the draft is equivalent to its saved content.

### Improved

- `/etc/hosts` writes now run serially through their commits, preventing rapid profile toggles, real-time applies, and backup restores from failing because of concurrent writes.
- Backup maintenance synchronizes records before pruning files and preserves backups referenced by records; backup deletion and restore state roll back when saving fails.
- Restoring a backup to `/etc/hosts` disables all user profiles so later edits cannot overwrite the restored content.
- Exact duplicate entries are merged when enabling profile combinations. The apply flow can remove exact duplicates across applied profiles, while hostname conflicts still block writes.
- Settings now include a software update status card. Profile, backup, and error controls have clearer copy and accessibility labels.

### Fixed

- Corrected profile switches falling out of sync with the actual `/etc/hosts` state. New, imported, and duplicated profiles now default to unapplied.
- Fixed repeated write failures after external edits and lost follow-up real-time applies.
- Fixed application state being rolled back or overwritten after a file write succeeded but its Core Data commit failed.

### Release

- Separate arm64 (Apple Silicon) and x86_64 (Intel) DMGs with sha256 checksums.

## 0.1.0-beta (6) - 2026-10-26

First public beta release.

- Profile-based `/etc/hosts` management with one-click switching, combinable profiles, structured list editing, and raw source editing.
- Real-time apply, conflict and duplicate detection, automatic timestamped backups with restore.
- Optional silent background writes through a signed privileged helper.
- Built-in update checks: automatically checks GitHub stable releases at most once per day, or on demand; downloads the DMG for the current architecture, verifies SHA-256 when available, and opens it after applying download quarantine metadata.
- Chinese and English interface, light and dark appearances.
- No telemetry or third-party analytics; GitHub Releases is contacted only for update checks.
- Open-source preparation: public bundle identifiers, shared schemes, MIT license, bilingual documentation, CI, and website.
- Helper signing validation now derives the trusted team from the helper's own signature so contributors can build with their own team.

### Packaging

- Separate arm64 (Apple Silicon) and x86_64 (Intel) DMGs with sha256 checksums.
- Ad-hoc signed beta builds; see the README installation notes for the Gatekeeper workaround.
