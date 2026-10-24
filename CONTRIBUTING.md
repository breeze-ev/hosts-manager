# Contributing

Thanks for considering a contribution to Hosts Manager.

## Getting Started

1. Fork the repository and create a topic branch.
2. Open `hosts-manager.xcodeproj` and build with your own development team.
3. Run the existing tests before opening a pull request.

```bash
xcodebuild test \
  -project hosts-manager.xcodeproj \
  -scheme hosts-manager \
  -destination 'platform=macOS' \
  -derivedDataPath build
```

## Expectations

- Keep changes scoped to the behavior or area described in the issue.
- Preserve the existing SwiftUI design language and bilingual copy.
- Add tests for parser, validator, backup, persistence, or helper contract changes.
- Do not add telemetry, analytics, network calls, or new third-party dependencies without a clear product need.
- Mention in the pull request when a change affects `/etc/hosts` writing or the helper.

## Helper Signing

The app and `HostsManagerHelper` must be signed by the same team. The helper reads its own signing team and uses it to build the code requirement for the caller, so a local development team works as long as both targets use it.

## Reporting Issues

Use the issue templates for bugs and feature requests. Security findings should be reported privately through GitHub Security Advisory instead of a public issue.
