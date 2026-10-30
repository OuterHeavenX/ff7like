# Echoes of the Last Dawn

An original, story-driven 2.5D JRPG built in **Godot 4.4.1** (Compatibility renderer): pixel-art billboard characters in low-poly, vertex-lit 3D towns and dungeons; an active-time party battle system with a Wait mode; jobs, JP and team "Resonance" techniques.

> **Build status (honest):** this repository currently contains a complete, playable **Prologue + Chapter One** (Bellweather and the Station Undercroft) — an estimated 45–60 minutes, *not yet measured by a human playtest* — plus the systems foundation for the full campaign. Chapters Two–Eight and the epilogue are planned in `docs/CAMPAIGN.md` but **not built**. See `docs/PROGRESS.md`.

## Play
- **Browser:** export with `tools/build.sh`, then serve `dist/web/` (any static server, e.g. `python3 -m http.server -d dist/web`). Single-threaded export: no special headers needed.
- **Linux / Steam Deck:** extract the `linux-x86_64.tar.gz` package and run `EchoesOfTheLastDawn.x86_64`. See `docs/STEAM_DECK_README.txt`.
- **From source:** open the folder in Godot 4.4.1 and press Play.

## Controls (rebindable in Settings > Controls)
| Action | Keyboard | Gamepad (Steam Deck) | Touch |
|---|---|---|---|
| Move | WASD / Arrows | Left stick / D-pad | Drag left side |
| Confirm / Talk | Enter / Space / Z | A | A button / tap |
| Cancel / Back (hold: run) | Esc / X / Backspace / Shift | B | B button |
| Party talk (field) · Repeat (battle) | F / C | X | X button |
| Menu (field) · Auto-battle (battle) | Tab / V | Y | MENU |
| Journal | J / M | View | LOG |
| Pause | P / F1 | Menu | II |
| Tabs / party member | Q / E, PgUp / PgDn | L1 / R1 | tap tabs |

Battle: Wait mode is default — time pauses while you choose. Tap enemies or party rows directly to target.

## Build, test, release
```
python3 tools/gen_art.py         # regenerate original pixel art (deterministic)
python3 tools/gen_audio.py       # regenerate original music + SFX (needs numpy, ffmpeg)
python3 tools/validate_content.py
godot --headless --import
godot --headless -s res://tools/check_scripts.gd
godot --headless res://tests/test_runner.tscn
godot --headless -- --smoke      # dev-only traversal of the whole slice
bash tools/build.sh              # all of the above + Web/Linux export + packages + checksums
```
Godot export templates for 4.4.1 must be installed. CI: `.github/workflows/build.yml`. Publishing: `docs/RELEASE.md`.

## Layout
`scripts/core` services (Settings, Content, InputHub, GameState, Saves, Audio, Router) · `scripts/world` map builder, field, events · `scripts/battle` simulation + presentation · `scripts/ui` menus · `content/` authoritative JSON data · `assets/` generated art/audio + OFL font · `tools/` generators, validator, build · `tests/` suites and dev harnesses · `docs/` design, campaign, QA, release.

## Licenses
Code: MIT (`LICENSE`). Assets: see `docs/ASSET_LICENSES.md`.
