# Progress

_Last updated: 2026-10-30 (session 1)._

## Milestone status
| Milestone | Status |
|---|---|
| A — Bootable foundation | **Done.** Title, new game, settings, field map, keyboard/gamepad/touch, NPC talk, collision, saves, Web + Linux exports tested. |
| B — Vertical slice | **Done, pending human playtest.** Prologue + Chapter One playable end-to-end (verified by the traversal harness and partial browser runs). Estimated 45–60 min, not measured. |
| C — Systems complete | **Partial.** Done: 8 characters as data, 12 jobs × 9 abilities + mastery implemented and functional, statuses, Resonance, inventory/equipment/optimize, journal, bestiary, save migration/transfer, accessibility, validators, rebinding. Missing: recruit flow for 5 later characters, crafting (recipes table empty), world map beyond Bellweather, repeatable activities, NG+ (stretch). |
| D — Campaign production | Not started (Ch2–Ch8 planned in CAMPAIGN.md). |
| E — Side content & endgame | Not started beyond Ch1 side quests. |
| F — Release candidate | Not started. Packaging pipeline exists and works. |

## Tested (see QA.md for commands and results)
Content validator, script compile check, 45 headless tests, full slice traversal, Web export (Chromium/SwiftShader: play, save, reload, continue; mobile touch emulation), Linux export run.

## Blockers / needs owner
- Real-device checks (iPhone, iPad, Android, Steam Deck) — no devices available here.
- Publishing (GitHub remote, itch.io page, butler key) — needs owner's accounts and explicit go-ahead.
- License choice for original assets (DECISIONS #17).

## Exact next task
1. Human playtest of Prologue + Ch1 with a timer; record in QA.md; tune encounter rate/enemy HP if fights feel long.
2. Begin **Chapter Two — The Rainward Line** as one validated content batch: region art (rail tiles exist: `rail`), 2 towns/stops (Rainward Junction, Millbrook Halt), the stalled freight train dungeon (3 maps), Nessa and Sera recruitment events, Ranger job unlock, 8 new enemy types (rail region), boss, first major choice (expose the Millbrook station vs. protect its workers) with consequences flagged for Ch5. Add a world-map screen node for rail travel.
3. After Ch2: run validator + tests + `--smoke` extended to Ch2; update CONTENT_MANIFEST and this file.
