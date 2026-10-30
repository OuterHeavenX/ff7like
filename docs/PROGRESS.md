# Progress

_Last updated: 2026-10-30 (session 1, after Chapter Two)._

## Milestone status
| Milestone | Status |
|---|---|
| A — Bootable foundation | **Done.** Title, new game, settings, field map, keyboard/gamepad/touch, NPC talk, collision, saves, Web + Linux exports tested. |
| B — Vertical slice | **Done, pending human playtest.** Prologue + Chapter One playable end-to-end (verified by the traversal harness and partial browser runs). Estimated 45–60 min, not measured. |
| C — Systems complete | **Partial.** Done: 8 characters as data, 12 jobs × 9 abilities + mastery implemented and functional, statuses, Resonance, inventory/equipment/optimize, journal, bestiary, save migration/transfer, accessibility, validators, rebinding. Crafting (10 recipes, atomic, smithy/any stations) and bounty contracts (repeatable, cooldowns) done. Missing: recruit flow for 3 later characters (Ilyan, Orin, Tavi), world-map screen beyond the menu list, 2 more repeatable activities, NG+ (stretch). |
| D — Campaign production | **In progress.** Chapter Two built and traversal-tested. Ch3–Ch8 planned. |
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
2. Build **Chapter Three — Glass Orchard** as one validated batch (see CAMPAIGN.md): glasshouse town + orchard villages, the Glasshouse Vaults dungeon with season switching, Hexweaver unlock, start Tavi's optional chain, Garran's Glass Orchard backstory (personal stage 2), 8 enemy types, boss; extend `tests/smoke_route.gd` and `test_balance.gd` to Ch3.
3. Systems still owed for Milestone C: challenge arena + training grounds (repeatables 2–3), world-map screen beyond the menu list, optional recruits' quest chains.
