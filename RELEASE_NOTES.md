# Release Notes

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
