# Release Guide

## Build packages
```
bash tools/build.sh
```
Produces in `dist/packages/`:
- `echoes-of-the-last-dawn-<ver>-web.zip` — `index.html` at the ZIP root (verified by the script), single-threaded build, no cross-origin isolation required.
- `echoes-of-the-last-dawn-<ver>-linux-x86_64.tar.gz` — executable bit preserved (verified), plus README (Steam Deck steps), asset licenses.
- `…-linux-x86_64.zip` — convenience copy (may lose the exec bit; README explains `chmod +x`).
- `SHA256SUMS.txt`.

## GitHub
The repository is ready to push (`.gitignore` excludes `.godot/`, `dist/*`). No remote is configured and nothing has been pushed by the agent. To publish:
```
git remote add origin git@github.com:<you>/<repo>.git
git push -u origin <branch>
```
CI (`.github/workflows/build.yml`) installs Godot 4.4.1 + templates, validates, tests, exports and uploads packages as artifacts.

## itch.io (not performed — needs your account)
1. Create the project page (Kind: HTML). Upload the web ZIP and tick "This file will be played in the browser".
2. Embed settings tested in development: **viewport 1280×720**, "Mobile friendly" on, orientation **landscape**, "Automatically start on page load" off (needs a click for audio), fullscreen button on. `SharedArrayBuffer` support **not** required.
3. Upload the Linux tar.gz, tag it Linux.
4. Or use butler (separate channels): `ITCH_USER=<you> BUTLER_API_KEY=<key> tools/butler_upload.sh` → `<you>/echoes-of-the-last-dawn:html5` and `:linux`.

### Suggested page copy
**Echoes of the Last Dawn** — *What the bells forget, we carry.*
On Lanternwake night in the canal town of Bellweather, the great bell tolls wrong and a whole street forgets Rowan's sister. Rowan doesn't. An original story-driven 2.5D JRPG with pixel-art characters in lantern-lit low-poly towns, an active-time battle system with a Wait mode, jobs and JP, and team Resonance techniques.
This early build contains the Prologue and Chapter One (~45–60 min, estimated). Keyboard, gamepad and touch supported. Saves stay in your browser; use Load Game → Export to back them up.
Content: mild fantasy violence; themes of memory loss and grief.

## Steam Deck
See `docs/STEAM_DECK_README.txt` (shipped inside the Linux package as README.txt). Native Linux build — do not force Proton. Not "Steam Deck Verified" (only Valve can grant that).
