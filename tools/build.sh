#!/usr/bin/env bash
# Reproducible build: import, validate, test, export Web + Linux, package.
# Requires Godot 4.4.1-stable on PATH as `godot` (or set GODOT=/path/to/godot)
# with matching export templates installed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
VERSION="$(grep -m1 'config/version=' project.godot | cut -d'"' -f2)"
echo "== Echoes of the Last Dawn $VERSION =="
"$GODOT" --version
echo "== Content validation (python) =="
python3 tools/validate_content.py
echo "== Import =="
"$GODOT" --headless --import >/dev/null 2>&1 || true
echo "== Script check =="
"$GODOT" --headless -s res://tools/check_scripts.gd
echo "== Tests =="
"$GODOT" --headless res://tests/test_runner.tscn
rm -rf dist/web dist/linux
mkdir -p dist/web dist/linux
echo "== Export Web =="
"$GODOT" --headless --export-release "Web" dist/web/index.html
echo "== Export Linux =="
"$GODOT" --headless --export-release "Linux" dist/linux/EchoesOfTheLastDawn.x86_64
chmod +x dist/linux/EchoesOfTheLastDawn.x86_64
bash tools/package.sh "$VERSION"
