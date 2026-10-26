#!/bin/bash
# Increment CURRENT_PROJECT_VERSION (build number) for all targets by 1.
set -euo pipefail

PBXPROJ="${SRCROOT:-$(cd "$(dirname "$0")/.." && pwd)}/hosts-manager.xcodeproj/project.pbxproj"

/usr/bin/env python3 - "$PBXPROJ" <<'EOF'
import re, sys

path = sys.argv[1]
with open(path) as f:
    content = f.read()

def bump(m):
    return "CURRENT_PROJECT_VERSION = %d;" % (int(m.group(1)) + 1)

content, n = re.subn(r"CURRENT_PROJECT_VERSION = (\d+);", bump, content)
with open(path, "w") as f:
    f.write(content)
print("Bumped build number in %d places" % n)
EOF
