# Progress

_Last updated: 2026-10-31 (v0.5.0: 3D characters, wayfinding, gamepad harness)._

## Milestone status
| Milestone | Status |
|---|---|
| A — Bootable foundation | **Done.** Title, new game, settings, field map, keyboard/gamepad/touch, NPC talk, collision, saves, Web + Linux exports tested. |
| B — Vertical slice | **Done, pending human playtest.** Prologue + Chapter One playable end-to-end (verified by the traversal harness and partial browser runs). Estimated 45–60 min, not measured. |
| C — Systems complete | **Partial.** Done: 8 characters as data, 12 jobs × 9 abilities + mastery implemented and functional, statuses, Resonance, inventory/equipment/optimize, journal, bestiary, save migration/transfer, accessibility, validators, rebinding. Crafting (10 recipes, atomic, smithy/any stations) and bounty contracts (repeatable, cooldowns) done. Missing: recruit flow for 3 later characters (Ilyan, Orin, Tavi), world-map screen beyond the menu list, 2 more repeatable activities, NG+ (stretch). |
| D — Campaign production | **In progress.** Chapters Two and Three built and traversal-tested. Ch4–Ch8 planned. |
| E — Side content & endgame | Not started beyond Ch1 side quests. |
| F — Release candidate | Not started. Packaging pipeline exists and works. |

## Tested (see QA.md for commands and results)
Content validator, script compile check, 45 headless tests, full slice traversal, Web export (Chromium/SwiftShader: play, save, reload, continue; mobile touch emulation), Linux export run.

## Since Chapter Three (v0.5.0)
3D character models (field + battle party), minimap / exit signs / objective marker / edge arrow / Map page, gamepad harness (62 checks, Steam Deck layout), main-menu focus fix, optional itch.io CI upload.

## Blockers / needs owner
- Real-device checks (iPhone, iPad, Android, Steam Deck) — no devices available here.
- itch.io: create the page, then add repo secret `BUTLER_API_KEY` + variable `ITCH_TARGET` (docs/RELEASE.md); CI then uploads every build.
- License choice for original assets (DECISIONS #17).

## Exact next task
1. Human playtest of Prologue + Ch1 with a timer; record in QA.md; tune encounter rate/enemy HP if fights feel long.
2. Build **Chapter Four — The Salt Archive** as one validated batch (see CAMPAIGN.md): coastal city + flooded library dungeon with tide timing (map patches on a tide flag toggled by a timer/levers), memory fragments as keys, Ilyan's recruitment (story), Sentinel unlock, Captain Ferro's deadline for Nessa (personal stage 2), 8 enemy types, boss; extend `tests/smoke_route.gd` and `test_balance.gd`. Pattern: copy the Ch3 batch structure (art fns in gen_art.py → data tables → maps → events → harness → sims → shots).
3. Systems still owed for Milestone C: challenge arena + training grounds (repeatables 2–3), world-map screen beyond the menu list, optional recruits' quest chains.
