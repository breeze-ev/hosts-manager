# Security Policy

Hosts Manager writes to `/etc/hosts`, a system file that requires elevated privileges. The privileged path is intentionally narrow.

## Supported Versions

The current unreleased source tree is supported on macOS 26 and newer. Security fixes will be applied to the default branch and included in the next published release.

## Reporting a Vulnerability

Please report security issues privately through the GitHub Security Advisory workflow instead of opening a public issue. Include a description of the issue, affected versions, steps to reproduce, and any suggested fix.

## Threat Model

- The app is not sandboxed because it must interact with the LaunchDaemon helper and read `/etc/hosts`.
- `HostsManagerHelper` runs as root and only exposes a validated hosts-write operation over XPC.
- The helper verifies that the caller is the Hosts Manager app signed by the same team as the helper.
- All writes pass through `HostsAtomicFileWriter`, which validates content, writes atomically, and preserves file permissions.
- The app creates timestamped backups before writes and keeps a configurable number of backups.

## Reporting Outside GitHub

If GitHub Security Advisory is unavailable, create a private issue or email the maintainer through the address shown in the commit history. Do not include credentials or personal data in the report.
