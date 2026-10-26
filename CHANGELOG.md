# Changelog

## 0.1.0-beta (6) - 2026-10-26

First public beta release.

- Profile-based `/etc/hosts` management with one-click switching, combinable profiles, structured list editing, and raw source editing.
- Real-time apply, conflict and duplicate detection, automatic timestamped backups with restore.
- Optional silent background writes through a signed privileged helper.
- Chinese and English interface, light and dark appearances.
- No telemetry, no network access, no third-party analytics.
- Open-source preparation: public bundle identifiers, shared schemes, MIT license, bilingual documentation, CI, and website.
- Helper signing validation now derives the trusted team from the helper's own signature so contributors can build with their own team.

### Packaging

- Separate arm64 (Apple Silicon) and x86_64 (Intel) DMGs with sha256 checksums.
- Ad-hoc signed beta builds; see the README installation notes for the Gatekeeper workaround.
