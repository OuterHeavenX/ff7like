#!/usr/bin/env bash
# Packages dist/web and dist/linux into itch.io-ready archives with checksums.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-$(grep -m1 'config/version=' project.godot | cut -d'"' -f2)}"
OUT="dist/packages"
rm -rf "$OUT"
mkdir -p "$OUT"
# Web: index.html must be at the ZIP root (no enclosing folder) for itch.io.
( cd dist/web && zip -q -9 -r "../../$OUT/echoes-of-the-last-dawn-$VERSION-web.zip" . )
# Linux: tar.gz preserves the executable bit; ZIP offered as a convenience.
STAGE="dist/stage/EchoesOfTheLastDawn-$VERSION-linux"
rm -rf dist/stage
mkdir -p "$STAGE"
cp dist/linux/EchoesOfTheLastDawn.x86_64 dist/linux/EchoesOfTheLastDawn.pck "$STAGE/"
cp docs/STEAM_DECK_README.txt "$STAGE/README.txt"
cp LICENSE "$STAGE/LICENSE.txt" 2>/dev/null || true
cp docs/ASSET_LICENSES.md "$STAGE/ASSET_LICENSES.md"
chmod +x "$STAGE/EchoesOfTheLastDawn.x86_64"
tar -C dist/stage -czf "$OUT/echoes-of-the-last-dawn-$VERSION-linux-x86_64.tar.gz" "$(basename "$STAGE")"
( cd dist/stage && zip -q -9 -r "../../$OUT/echoes-of-the-last-dawn-$VERSION-linux-x86_64.zip" "$(basename "$STAGE")" )
# Verify archives.
WEB_LIST="$(unzip -l "$OUT/echoes-of-the-last-dawn-$VERSION-web.zip")"
grep -q " index.html$" <<< "$WEB_LIST" || { echo "web zip missing root index.html"; exit 1; }
for f in index.js index.wasm index.pck; do grep -q " $f$" <<< "$WEB_LIST" || { echo "web zip missing $f"; exit 1; }; done
TAR_LIST="$(tar -tzvf "$OUT/echoes-of-the-last-dawn-$VERSION-linux-x86_64.tar.gz")"
grep -q "rwxr-xr-x.*EchoesOfTheLastDawn.x86_64" <<< "$TAR_LIST" || { echo "linux tarball missing exec bit"; exit 1; }
grep -q "EchoesOfTheLastDawn.pck" <<< "$TAR_LIST" || { echo "linux tarball missing pck"; exit 1; }
( cd "$OUT" && sha256sum * > SHA256SUMS.txt )
cat "$OUT/SHA256SUMS.txt"
ls -la "$OUT"
