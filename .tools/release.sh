#!/usr/bin/env bash
# Build a local release zip in .release/ using BigWigsMods/packager (no upload).
# Requires: bash, curl, git, svn, zip. Extra args pass through to release.sh.
set -euo pipefail

# Same packager commit as .github/workflows/release.yml (v2.6.1)
PACKAGER_REF="e50a250f8705041e40f2fa1ddcb280a686d65aa0"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$(mktemp)"
trap 'rm -f "$script"' EXIT

curl -fsSL "https://raw.githubusercontent.com/BigWigsMods/packager/$PACKAGER_REF/release.sh" -o "$script"
bash "$script" -d -t "$root" "$@"
