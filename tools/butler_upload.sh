#!/usr/bin/env bash
# Upload packages to itch.io with butler. Requires BUTLER_API_KEY in the
# environment (never commit it). Fill in your itch.io account/project.
set -euo pipefail
ITCH_USER="${ITCH_USER:-YOUR_ITCH_USERNAME}"
ITCH_GAME="${ITCH_GAME:-echoes-of-the-last-dawn}"
VERSION="${1:-$(grep -m1 'config/version=' "$(dirname "$0")/../project.godot" | cut -d'"' -f2)}"
PKG="$(dirname "$0")/../dist/packages"
if [[ "$ITCH_USER" == "YOUR_ITCH_USERNAME" ]]; then echo "Set ITCH_USER (and optionally ITCH_GAME) first."; exit 1; fi
command -v butler >/dev/null || { echo "Install butler: https://itch.io/docs/butler/"; exit 1; }
butler push "$PKG/echoes-of-the-last-dawn-$VERSION-web.zip" "$ITCH_USER/$ITCH_GAME:html5" --userversion "$VERSION"
butler push "$PKG/echoes-of-the-last-dawn-$VERSION-linux-x86_64.tar.gz" "$ITCH_USER/$ITCH_GAME:linux" --userversion "$VERSION"
