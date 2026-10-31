#!/usr/bin/env bash
# Upload packages to itch.io with butler. Requires BUTLER_API_KEY in the
# environment (never commit it) and ITCH_TARGET=<itch-user>/<game-slug>.
# CI does the same automatically (job deploy-itch) once the repository has a
# BUTLER_API_KEY secret and an ITCH_TARGET variable.
set -euo pipefail
ITCH_TARGET="${ITCH_TARGET:-${ITCH_USER:+$ITCH_USER/${ITCH_GAME:-echoes-of-the-last-dawn}}}"
VERSION="${1:-$(grep -m1 'config/version=' "$(dirname "$0")/../project.godot" | cut -d'"' -f2)}"
PKG="$(dirname "$0")/../dist/packages"
if [[ -z "$ITCH_TARGET" ]]; then echo "Set ITCH_TARGET=<itch-user>/<game-slug> first."; exit 1; fi
command -v butler >/dev/null || { echo "Install butler: https://itch.io/docs/butler/"; exit 1; }
butler push "$PKG/echoes-of-the-last-dawn-$VERSION-web.zip" "$ITCH_TARGET:html5" --userversion "$VERSION"
butler push "$PKG/echoes-of-the-last-dawn-$VERSION-linux-x86_64.zip" "$ITCH_TARGET:linux" --userversion "$VERSION"
