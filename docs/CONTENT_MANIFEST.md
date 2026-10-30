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
| arena_town, arena_undercroft, arena_bellcore, arena_rail, arena_train | Battle arenas | — | Built |
| rainward_junction | Rail hub (rain) | barge ↔ Wick dock, freight (E) | Built |
| freight_cars | Dungeon (train interior, locked brake car patch) | junction (W), cutting (E) | Built |
| millbrook_cutting | Dungeon (rain, boss) | freight (W), halt (E, after boss) | Built |
| millbrook_halt | Village | cutting (W); freight departure trigger | Built |
| verrins_glass | Town (glasshouses, orchard) | rail (W: freight to Junction/Halt, Ch3 end), vaults (E), hollin (S) | Built |
| hollin_ward | Village | verrins_glass | Built |
| glass_vaults | Dungeon with season patches (`vault_winter`) | verrins_glass (W), vaults_core (E) | Built |
| vaults_core | Boss room | glass_vaults | Built |
| arena_orchard, arena_vault | Battle arenas | — | Built |

## Characters (`content/characters.json`)
rowan, mira, garran (Ch1), nessa, sera (Ch2), tavi (Ch3, optional chain) — joinable. ilyan (story) and orin (optional) — fully defined but **not yet recruitable**.

## Jobs (`content/jobs.json`)
All 12 defined with 6 actives + 3 passives + mastery (108 abilities, all referencing implemented skill ops). Obtainable now: wayfarer, vanguard, artificer (start), duelist, arcanist, mender (Hask), ranger (Nessa, Ch2), hexweaver (Mother Sorrel, Ch3), cantor (Tavi, Ch3). Locked with documented unlock: sentinel, chronist, bellbound.

## Enemies (`content/enemies.json`)
warden (aggressor), warden_sergeant (protector), brass_rat (aggressor), echo_moth (disruptor), tallow_wisp (elemental), rust_mender (healer), silt_crab (protector/armored), hollow_echo (summoner), echo_mote (summon, no rewards), ironside (optional elite), hollow_clapper (boss, 3 phases). Ch2: rust_hound (aggressor, pack haste), signal_wraith (disruptor), coal_golem (protector, absorbs fire), rail_spider (disruptor, poison/slow), spore_toad (healer), storm_kite (elemental, absorbs storm), memory_leech (disruptor, drain/silence), line_marksman (back-row aggressor, mark+snipe), signal_warden (boss, element-shifting phases). Ch3: glass_beetle (protector, party Barrier), orchard_crow (aggressor, dives on sleepers), pollen_sprite (disruptor, sleep), root_mender (healer, regen), sap_slime (summoner, buds), frost_bloom / ember_bloom (seasonal elementals), orchard_overseer (commander, party haste), vine_graft (boss summon), harvest_engine (boss). Encounters go_crows / go_crow_sprite are defined but not yet placed. warden_sergeant/story_sergeant encounter is defined but not yet placed.

## Quests (`content/quests.json`)
mq_sealed_fork (main, prologue) · mq_street_forgot (main, ch1) · sq_lamplighter (side) · sq_small_debts (side, branching: truth/mercy) · sq_night_crew (side) · pq_mira_1, pq_garran_1 (personal stage 1). Ch2: mq_rainward (main, with major choice), pq_nessa_1, pq_sera_1 (personal), sq_names_doors (side), sq_rain_rations (side, branching paid/seal). Ch3: mq_glass_orchard (main, choice), pq_garran_2, pq_tavi_recruit (optional recruit), sq_bread_hollin (side, branching paid/persuaded).

## Items, shops, events
74 items; 7 shops; 10 recipes; 8 contracts; 167 events in `content/events/prologue.json`, `chapter1.json`, `chapter2.json`, `chapter3.json`.

## Assets
22 character sprite sets (8 party + 14 NPC types) × field/battle/5 portraits; 11 enemy sheets; 32-tile atlas; FX sheet; status & element icons; 9 music loops; 31 SFX. All generated; see ASSET_LICENSES.md.
