# Content Manifest

Validation: `python3 tools/validate_content.py` (engine-free) and `tests/test_content.gd` (in-engine walkability & reachability). Last run: both pass (see QA.md).

## Maps (`content/maps`)
| ID | Kind | Connections | Status |
|---|---|---|---|
| bellweather_wick | Town exterior | square (E), vale_home (door), undercroft_upper (hatch) | Built |
| bellweather_square | Town hub | wick (W), station (N, sealed after toll until boss), post_office, copper_kettle | Built |
| bellweather_station | Plaza | square (S) | Built |
| vale_home, post_office, copper_kettle | Interiors | parent street/square | Built |
| undercroft_upper | Dungeon 1/3 | wick (ladder), cistern (S) | Built |
| undercroft_cistern | Dungeon 2/3 | upper (N), core (S); drained-channel patch | Built |
| undercroft_core | Dungeon 3/3 (boss) | cistern (N) | Built |
| arena_town, arena_undercroft, arena_bellcore | Battle arenas | — | Built |

## Characters (`content/characters.json`)
rowan, mira, garran — joinable (story). sera, ilyan, nessa (story) and orin, tavi (optional) — fully defined (stats, growth, personal skills, sprites, portraits) but **not yet recruitable** (later chapters).

## Jobs (`content/jobs.json`)
All 12 defined with 6 actives + 3 passives + mastery (108 abilities, all referencing implemented skill ops). Obtainable now: wayfarer, vanguard, artificer (start), duelist, arcanist, mender (Hask). Locked with documented unlock: ranger, cantor, hexweaver, sentinel, chronist, bellbound.

## Enemies (`content/enemies.json`)
warden (aggressor), warden_sergeant (protector), brass_rat (aggressor), echo_moth (disruptor), tallow_wisp (elemental), rust_mender (healer), silt_crab (protector/armored), hollow_echo (summoner), echo_mote (summon, no rewards), ironside (optional elite), hollow_clapper (boss, 3 phases). warden_sergeant/story_sergeant encounter is defined but not yet placed.

## Quests (`content/quests.json`)
mq_sealed_fork (main, prologue) · mq_street_forgot (main, ch1) · sq_lamplighter (side) · sq_small_debts (side, branching: truth/mercy) · sq_night_crew (side) · pq_mira_1, pq_garran_1 (personal stage 1).

## Items, shops, events
44 items (consumables, materials, key items, equipment); shops: festival_stall, forge, undercroft_cache; 92 events in `content/events/prologue.json` and `chapter1.json`.

## Assets
22 character sprite sets (8 party + 14 NPC types) × field/battle/5 portraits; 11 enemy sheets; 32-tile atlas; FX sheet; status & element icons; 9 music loops; 31 SFX. All generated; see ASSET_LICENSES.md.
