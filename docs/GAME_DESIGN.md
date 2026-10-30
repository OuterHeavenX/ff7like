# Game Design Reference

## World
Asterreach: beneath each city a buried bell keeps the seasons. The **Meridian Authority** (a civic utility, not an empire) tolls the bells to extract stored memory, which stabilises weather and harvests. Benefits are real (no floods in Bellweather's lower wards, no famine on the Rainward Line); costs are hidden (villages losing histories, people forgetting loved ones). Factions: Authority directorate, Wardens (city enforcement), Engineers' Guild (Mira's colleagues, internal dissent), Records Hall archivists, orchard cooperatives that depend on extraction. Central antagonist (planned): **Director Aurel Vance**, who sincerely believes permanent managed peace is worth personal memory and choice. Adjunct Corwin Sallow is a mid-level instrument of that policy.

## Art spec (fixed)
- 24 px = 1 world unit = 1 map tile. Field sprites 24×32 (3 frames × 4 directions). Battle sprites 32×32 × 8 poses (idle, ready, windup, strike, cast, hurt, KO, victory). Portraits 64×64 × 5 expressions. Tiles 24×24 in an 8×8 atlas.
- Sprites are upright Y-billboards with vertical scale 1/cos(camera pitch) to cancel foreshortening (no backward lean, no wall clipping). Field camera: perspective FOV 30°, pitch 40°, fixed yaw.
- Lighting is baked into vertex colours at map build (ambient + lamp falloff + face shading + corner AO). Glow = additive halo billboards (one MultiMesh). Water = pixel-snapped unshaded shader. No dynamic lights or post-processing required.
- All art/audio is produced by `tools/gen_art.py` / `tools/gen_audio.py` (deterministic, original).

## Maps (data: `content/maps/*.json`)
Rows of legend characters (`content/maps/_legend.json`) + optional height digits (1 level = 0.5 units). Stairs connect levels along one axis. Props, lights, NPCs (with conditions), triggers (step/interact, exits, events), chests (one-time IDs), spawns, encounter tables, party-talk, conditional tile patches (e.g. drained channel). Encounters never fire within 2 tiles of triggers/spawns/NPCs, with a step minimum and post-battle grace.

## Battle
Active-time gauges; **Wait** (default) pauses the timeline while a command or target menu is open; **Active** keeps time flowing; battle speed 1–5. Simulation (`battle_sim.gd`) is pure and seeded; presentation consumes its event lists.
- Commands: Attack, personal command, main-job skills, secondary skills, Resonance arts, Item, Guard, Row, Escape (where allowed), Repeat (target re-validated), Auto (never spends items; any button cancels).
- Damage: `power% × ATK|MAG × 1.5 × (1 − DEF/(DEF + 40 + 4·attacker level))`, element (weak 1.5, resist 0.5, immune 0, absorb heals), ±8% variance, crit ×1.6, back row (melee dealt ×0.6, physical taken ×0.7), Guard ×0.5, Barrier ×0.67, Vulnerable ×1.3. Minimum 1. Normal attacks never miss unless Blind or the target has explicit evasion.
- Statuses (durations count the affected unit's own turns, so nothing ticks during paused menus): poison 6%/turn, burn 4%/turn & ATK×0.85 & heal×0.75, slow ×0.6 gauge, haste ×1.5 (cancel each other), sleep (wakes when hit; brief immunity after), silence (magic & songs; gadgets/items still work), blind (½ physical accuracy), regen 8%/turn, barrier, stun (lose next turn, breaks charges, then 2 turns immunity — no stun-lock), vulnerable, mark (+20% crit taken), guard, cover (intercept single-target physical), challenge/taunt, riposte. Reapplying refreshes (no stacking). Bosses use partial resistances, not blanket immunity.
- Resonance (0–100, shared): built by complementary play (exploit weakness +10, hit marked/vulnerable +6, heal an ally under 30% +6, inflict a status +4, guard absorbing a hit +4, +2 per action). Spent on character-pair techniques (50) or a trio technique (100). Taught when it first reaches 50.
- Enemy roles: aggressor, protector (Cover/Barrier), healer, disruptor, elemental, summoner (summons give no rewards and are capped), elite, boss (phases, telegraphed charges that Guard mitigates and Stun breaks).
- Anti-loop: time gifts capped at +50 and never self-targeted; delayed effects cannot schedule delays; counters cannot be countered.

## Progression
- XP: `xp_to_next(L) = round(14 + 7·L^1.85)`, levels 1–99. Main story target finish ~Lv 45–55 (to be tuned per chapter).
- JP: earned by the current main job. Job rank from total JP earned (thresholds 0/60/180/400/750/1250/2000/3000 → ranks 1–8). Abilities cost JP, may require rank and prerequisite abilities. JP spent is permanent (no refunds); learned abilities are never lost; changing jobs is free.
- Each character keeps a personal command; equips a main job (stat modifiers + skills + JP), a secondary skill set (learned actives of another job) and up to 3 learned passives from any job. Mastering every ability of a job grants a permanent mastery bonus.
- Reserves: 75% XP (×2 catch-up when more than 2 levels below the active party average), 50% JP. KO'd active members get half shares. KO'd members revive at 1 HP after victory.
- 12 jobs × (6 actives + 3 passives + mastery) are implemented as data and functional in the battle system. In the current build 6 jobs are obtainable (Wayfarer, Vanguard, Artificer at start; Duelist, Arcanist, Mender from Hask); the rest list their planned unlock and are locked.

## Saves
3 manual slots + 3 rotating autosaves (only after a real game has begun), metadata (location, chapter, party, level, playtime, timestamp, build, schema). Atomic write: temp file → read-back verification → previous file kept as `.bak` → rename. Versioned schema with migrations; unknown IDs are dropped gracefully; corrupted files fall back to the backup. Portable JSON export/import (browser download / file picker; native `user://exports` and `user://imports`). Device preferences live separately in `user://settings.cfg`.

## Crafting (focused)
`content/recipes.json`: consumables (any crafting spot: Tamsin's cache) and equipment upgrades (smithies: Dunmore, Hobb). Recipes list exact materials, crowns and station; crafting is atomic (all inputs checked before anything is consumed) and upgrades require unequipping the base item. Materials come from enemy drops shown in the Bestiary.

## Repeatable activities
1. **Bounty contracts** (`content/contracts.json`, boards in Lantern Square and Rainward Junction): accept → defeat N of a target anywhere (only defeats after acceptance count; summons never count) → turn in for crowns, items and JP to the active party → cooldown of N won battles → repeatable. Built.
2. Challenge arena with ranked rule-variant fights — planned (Ch7 / postgame).
3. Training grounds with high-JP rare spawns — planned (Ch7).
