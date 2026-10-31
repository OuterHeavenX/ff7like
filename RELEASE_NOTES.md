# Release Notes

## 0.5.0 — 3D characters, wayfinding, Steam Deck controls pass
- **3D characters.** Party members and townsfolk are now low-poly 3D models (rounded-box chibi style with an outline, pixel faces that blink, walk cycles, smooth turning, lit by nearby lamps). Party members in battle use the same models with weapons and poses for attack, cast, hurt, KO and victory. Settings > Audio & Display > Characters switches back to the classic pixel sprites. Enemies are still pixel art.
- **Wayfinding so you don't get lost.**
  - Minimap in the top-right corner (Settings > Gameplay > Minimap): terrain, exits, people, you, and the objective.
  - Every exit has a floating sign naming where it leads, with floor arrows at the map edges.
  - Gold objective marker over the person or place to go next. If it's in another area, the exit that leads toward it turns gold.
  - An arrow at the screen edge points to the objective when it's off screen.
  - A line under the objective says where to head ("Head to Lantern Square, toward Post Office").
  - The pause menu's Map page shows a large map of the current area.
  - Objectives are worked out from the quest and event data, so every stage of all 16 quests is covered (checked by a test).
- **Gamepad / Steam Deck.** New harness (`godot -- --padtest`) drives the real game using only gamepad input in the Steam Deck layout and checks every bound button across the title screen, settings, field, dialogue, menus, shop, save screen, crafting, bounty board and battle (62 checks). Unbound buttons (L2/R2, L3/R3, right stick) are verified to do nothing.
- Fix: opening the main menu (Y / View / Menu or Tab / J / P) left nothing focused, so the D-pad and arrow keys did nothing until a shoulder button or the mouse was used. The menu now focuses its section list on open and after L1/R1.
- CI: optional automatic itch.io upload (butler) once a `BUTLER_API_KEY` secret and an `ITCH_TARGET` variable are added to the repository.

## 0.4.1 — iPhone fixes and automatic Pages deployment
- Touch controls: A/B/X/Menu/Log/Pause buttons were placed off-screen on iPhone in landscape (iOS reports screen size in portrait). Web builds no longer apply a device safe-area offset; native builds clamp it.
- Audio on iOS: game audio now plays with the silent switch on (playback audio session on Safari 17+, silent looping media element fallback), unlocked on the first tap.
- GitHub Actions now publishes each tested Web build to GitHub Pages automatically.

## 0.4.0 — Chapter Three: Glass Orchard
- New region: Verrin's Glass, Hollin Ward, the Glasshouse Vaults (season valves switch winter/summer routes and encounters), the Engine Chamber.
- Garran's backstory (personal stage 2), optional recruit Tavi via a song-collecting chain, Hexweaver and Cantor jobs.
- 8 new enemy types and the Harvest Engine boss; retune/shut-down choice; party-aware persuasion in a branching side quest.
- Crafting (consumables + equipment upgrades) and repeatable bounty contracts on three boards; save schema v3 (auto-migrates).

## 0.3.0 — Chapter Two: The Rainward Line
- New region: Rainward Junction (rain), the Stalled Freight, Millbrook Cutting, Millbrook Halt. Barge travel back to Bellweather keeps Chapter One content reachable.
- Nessa and Sera join (party of five with reserves); Ranger job unlocked.
- 8 new enemy types with distinct roles, a warden ambush, and the Signal Warden boss whose lamp colour changes its weaknesses.
- First major choice (Odile's logs: expose or protect), 2 side quests (one branching), 2 personal quest stages, new gear tier and shops.
- Fixes: boss framing in battle, tap-to-advance narration on touch, retry snapshot corruption, auto-battle policy.

## 0.2.0 — Prologue & Chapter One (early build)
- Playable Prologue "Lanternwake" and Chapter One "What the Street Forgot": Bellweather (Wick Street, Lantern Square, Bell Station, three interiors) and the Station Undercroft (3 dungeon maps, valve puzzle or optional elite route, boss).
- Party: Rowan, Garran, Mira. 6 obtainable jobs (12 implemented), JP learning, passives, secondary skill sets, Resonance arts.
- Active-time battles with Wait/Active modes, battle speed, repeat, auto-battle, row, guard, escape, telegraphed boss attacks.
- 3 side quests (one with branching outcomes), 2 personal quest stages, shops, inn, chests, bestiary, journal with recaps.
- 3 manual + 3 auto save slots, backups, migration, browser/desktop export & import.
- Keyboard, gamepad and touch controls; rebinding; accessibility options.
Known issues: see docs/QA.md. Later chapters are not yet built.
