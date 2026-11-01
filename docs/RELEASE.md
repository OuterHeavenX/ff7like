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

## GitHub Pages (live)
- URL: https://outerheavenx.github.io/ff7like/ — Pages source is the `gh-pages` branch, root folder (set in repository Settings → Pages).
- `gh-pages` holds only the exported Web files plus `.nojekyll`; it has its own history.
- Automatic: every push to `claude/echoes-of-the-last-dawn` runs `.github/workflows/build.yml`. If validation, tests, exports and the traversal harness pass, the `deploy-pages` job copies `dist/web` onto `gh-pages` as a normal commit (never forced) and Pages republishes. Pull requests and other branches build but do not deploy.
- The web build is an installable app (PWA: manifest + service worker, fullscreen, landscape). Files are served cache-first, so a new deploy reaches players like this: the browser downloads the new version in the background, and the title screen shows "A new version is ready - tap to update". Tapping it switches to the new version and reloads. The title screen shows the version.
- iPhone: Share > Add to Home Screen. Android/desktop Chrome: Install app. The installed app has its own storage; saves move across with Load Game > Export / Import.

## itch.io (not yet published — needs your account)
Nothing has been uploaded to itch.io. To publish:
1. On itch.io create the project page (Kind of project: **HTML**). Upload any web ZIP once and tick "This file will be played in the browser" (itch needs that tick on the html5 upload; butler keeps it on later pushes).
2. Embed settings tested in development: **viewport 1280×720**, "Mobile friendly" on, orientation **landscape**, "Automatically start on page load" off (a click is needed for audio), fullscreen button on. `SharedArrayBuffer` support **not** required.
3. **Automatic uploads from CI:** in the GitHub repo, Settings → Secrets and variables → Actions:
   - New repository **secret** `BUTLER_API_KEY` = an API key from https://itch.io/user/settings/api-keys
   - New repository **variable** `ITCH_TARGET` = `<your-itch-username>/<game-slug>` (e.g. `yourname/echoes-of-the-last-dawn`)
   After that, every push to `claude/echoes-of-the-last-dawn` that passes CI pushes the web ZIP to the `html5` channel and the Linux ZIP to the `linux` channel (job `deploy-itch`). Until both are set, the job logs a notice and uploads nothing.
4. Manual alternative: `ITCH_TARGET=<you>/<game> BUTLER_API_KEY=<key> tools/butler_upload.sh`.

### Suggested page copy
**Echoes of the Last Dawn** — *What the bells forget, we carry.*
On Lanternwake night in the canal town of Bellweather, the great bell tolls wrong and a whole street forgets Rowan's sister. Rowan doesn't. An original story-driven 2.5D JRPG with pixel-art characters in lantern-lit low-poly towns, an active-time battle system with a Wait mode, jobs and JP, and team Resonance techniques.
This early build contains the Prologue and Chapter One (~45–60 min, estimated). Keyboard, gamepad and touch supported. Saves stay in your browser; use Load Game → Export to back them up.
Content: mild fantasy violence; themes of memory loss and grief.

## Steam Deck
See `docs/STEAM_DECK_README.txt` (shipped inside the Linux package as README.txt). Native Linux build — do not force Proton. Not "Steam Deck Verified" (only Valve can grant that).
