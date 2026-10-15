#!/usr/bin/env bash
# Build a local release zip in .release/ using BigWigsMods/packager (no upload).
# Requires: bash, curl, git, svn, zip. Extra args pass through to release.sh.
set -euo pipefail

# The packager needs these on PATH: svn fetches the WowAce externals in
# .pkgmeta, zip builds the archive. Git for Windows ships neither.
missing=""
for tool in curl git svn zip; do
    command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
    echo "Missing on PATH:$missing. Install them first, then run this again." >&2
    exit 1
fi

# Same packager commit as .github/workflows/release.yml (v2.6.1)
PACKAGER_REF="e50a250f8705041e40f2fa1ddcb280a686d65aa0"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$(mktemp)"
trap 'rm -f "$script"' EXIT

curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_REF/release.sh" -o "$script"
bash "$script" -d -t "$root" "$@"
