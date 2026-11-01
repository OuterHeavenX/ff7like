# QA Log

All results below were actually run in the development container (Linux x86_64, 4 vCPU, no GPU) on 2026-10-30 unless marked otherwise.

## v0.6.0 checks (2026-11-01)
| Check | Command | Result |
|---|---|---|
| Unit/integration tests | `godot --headless res://tests/test_runner.tscn` | 64 passed, 0 failed (new: difficulty scaling incl. summons, reward multipliers, setting fallbacks, Story/Hard boss sims, natural-progression levels; play report objectives/battles/areas/export/off switch/clear) |
| Natural progression estimate (Normal) | `test_difficulty.gd` | Story battles + 10 random battles per chapter → **Lv6 / Lv11 / Lv15** before the three bosses (393 / 2207 / 5843 XP). **Estimate, not measured by a person.** |
| Chapter One boss sims (human-like policy, 10 seeds) | scratch harness | After −10% HP: Lv5 4/10, **Lv6 9/10**, Lv7 10/10, ~91 actions. Story Lv4–5: 10/10. Hard Lv8: about 4/10 before the HP change. |
| Traversal | `godot --headless -- --smoke` | ROUTE OK |
| Gamepad harness | `godot --headless -- --padtest` | PADTEST OK, 68 checks (new: New Game difficulty picker with A/B, Play report screen focus, D-pad, B) |
| Installable app (PWA) in Chromium/Playwright | scratch `pwatest.js`, `pwaupdate.js` | Manifest (fullscreen, landscape, icons 144/180/512) and service worker active; iPhone user agent shows the Add to Home Screen tip; **loads with the network off** after one online reload; after a new export, the title shows "A new version is ready", and one tap installs it and reloads. |
| Render cost with 3D characters (Xvfb, OpenGL 3) | scratch harness | Per-frame triangles (standard): Lantern Square 74.7k → **44.2k**, Rainward Junction 121k → **69.9k** after halving bevel segments; Low preset 12–20k; pixel sprites 4–6k. Draw calls 60–101 (standard), 39–64 (Low), 25–35 (pixel). Real phone frame rate still **unmeasured**. |

## v0.5.0 checks (2026-10-31)
| Check | Command | Result |
|---|---|---|
| Content validator | `python3 tools/validate_content.py` | OK — 8 characters, 203 skills, 74 items, 30 enemies, 16 quests, 167 events, 24 maps |
| Script compile | `godot --headless -s res://tools/check_scripts.gd` | 0 failures |
| Unit/integration tests | `godot --headless res://tests/test_runner.tscn` | 54 passed, 0 failed (new: every stage of all 16 quests resolves to an objective location; prologue route; hatch passage routing; every appearance spec builds a 3D model and runs every pose) |
| Traversal harness | `godot --headless -- --smoke` | ROUTE OK (Prologue → Chapter Three with 3D characters and wayfinding active) |
| **Gamepad harness (Steam Deck layout)** | `godot --headless -- --padtest` and under Xvfb at **1280×800** with `--out=` screenshots | **PADTEST OK, 62 checks**: title (any button, D-pad, stick, Settings tabs L1/R1, B back), New Game, dialogue (A), field (stick + D-pad in 4 directions, hold B to run, X party talk, A talk to NPC), Y menu (L1/R1 sections, D-pad, A in, B out/close), View journal, Menu pause, shop (focus, D-pad, R1 Buy/Sell, B), save screen, crafting, bounty board, battle (D-pad cursor, A attack → target, D-pad target, B cancel, A A submit, Y auto on, any button off, finish, A dismiss results). L2/R2, L3/R3, right stick verified inert. Events are injected through Godot's input pipeline (`Input.parse_input_event`), not a physical pad. |
| Bug found by the gamepad harness | — | Main menu opened with nothing focused (D-pad/arrows dead until L1/R1 or mouse). Fixed. |
| Exports | `bash tools/build.sh` | OK — `echoes-of-the-last-dawn-0.5.0-{web.zip, linux-x86_64.tar.gz, linux-x86_64.zip}` + SHA256SUMS; test harness code not in either PCK (only the engine's UID index lists the paths) |
| Linux binary | Xvfb 1280×800, OpenGL 3 | Runs 25 s to title with no script errors |
| Browser (Playwright, Chromium + SwiftShader) | mobile 844×390, touch, DPR 2 | New Game → walk with the virtual stick: 3D characters render, minimap sits under the Pause/Log buttons, objective hint + gold edge arrow shown, all touch buttons visible, no page errors |

## Automated (pass)
| Check | Command | Result |
|---|---|---|
| Content validator | `python3 tools/validate_content.py` | OK — 8 characters, 12 jobs, 158 skills, 44 items, 11 enemies, 13 encounters, 7 quests, 92 events, 12 maps |
| Script compile | `godot --headless -s res://tools/check_scripts.gd` | 0 failures |
| Unit/integration tests | `godot --headless res://tests/test_runner.tscn` | 49 passed, 0 failed (battle rules, statuses, targeting, rewards, progression, inventory, quests, saves/migration/corruption/import, content integrity incl. map reachability, balance sims) |
| Traversal harness | `godot --headless -- --smoke` | ROUTE OK — Prologue → Chapter Three end: all main/side/personal quests, optional elite, both bosses, Millbrook choice; real events, auto-battle, **simulated grinding (Lv10 before Ch1 boss, Lv13 before Ch2 freight, Lv19 before Ch3 boss)** |
| Web export | `--export-release "Web"` | OK (PCK 2.6 MB, WASM 43.7 MB uncompressed) |
| Linux export | `--export-release "Linux"` | OK; binary runs headless; only libc-level dynamic deps |
| Browser smoke (Playwright, Chromium + SwiftShader **emulated GPU**) | `node webtest2.js` (scratch) | Title → New Game → dialogue → walk → menu → **reload page → Continue restores autosave** (IndexedDB persistence) → no console errors |
| Mobile emulation (Playwright 844×390, touch, DPR 2) | same | Title renders in landscape; tap passes the gate |
| Rendered screenshots (Xvfb + llvmpipe) | `godot -- --shots` | Square, Wick, inn, cistern, core, menus, battle start/menu/targeting reviewed by eye |

## Balance simulations (deterministic, policy-driven; not human playtests)
| Encounter | Level | Win rate | Avg actions |
|---|---|---|---|
| Common undercroft groups | 4 | 100% | 7–13 |
| Ironside (optional elite) | 6 | 8/8 | 22 |
| Hollow Clapper (boss), human-like policy | 5 / 6 / 7 / 8 | 2/10, 6/10, 9/10, 10/10 | ~85–105 |
| Hollow Clapper, auto-battle (no items) | 7 / 8 / 10 | 0, 1, 10 of 10 | ~70 |
| Ch2 common groups (4-member party) | 10 | 100% | 12–17 |
| Signal Warden (boss), human-like policy | 10 / 11 / 12 / 13 | 6/8, 6/8, 8/8, 8/8 | ~110–125 |
| Ch3 common groups | 15 | 100% | 13–22 |
| Harvest Engine (boss) | 15 / 16 / 17 / 18 | 8/8 each | ~95–126 |
Estimated real duration (sim time + ~1.3 s per presented action + decision time): common fights ~25–45 s, boss ~4–6 min. **Unmeasured by a human.**

## Playtime
Chapter Three estimate: 60–80 min (not measured). Chapter Two estimate: 60–80 min (not measured). Prologue + Chapter One estimate: 45–60 min for a first-time player (dialogue ~92 events, ~12–18 random battles, 3 story battles, elite, boss). **Not measured.** The harness playtime figure (≈6 min at 6× speed with auto-advance) is not representative.

## Real-device reports
- **iPhone, mobile browser via GitHub Pages (v0.4.0, reported by the owner 2026-10-30):** game loads and the walking stick works. **Bugs:** (1) no A/B/X/Menu/Log/Pause buttons — right-side touch buttons were positioned off-screen because iOS reports screen width in portrait while landscape; (2) no sound — device was in silent mode, which mutes Web Audio on iOS. Both addressed in 0.4.1; **re-test pending.**

## Pending real-device checks (NOT done)
- [ ] iPhone Safari re-test of 0.4.1 (touch buttons visible, audio with silent switch on and off, save persistence in Safari ITP)
- [ ] iPad Safari
- [ ] Android Chrome
- [ ] Desktop Firefox / Safari / Chrome on real GPUs; itch.io iframe embed persistence
- [ ] Steam Deck hardware: Desktop Mode launch, Gaming Mode as non-Steam game, physical buttons (the harness covers the mapping, not the device), 1280×800 frame rate with 3D characters, suspend/resume
- [ ] Physical gamepad hotplug on desktop
- [ ] Human full playthrough of Prologue + Chapter One with timing

## Known issues
- Chapters 4–8 not built.
- Enemies are still 2D pixel sprites beside the 3D party; the classic pixel party is available in Settings.
- 3D character frame rate on real phones is unmeasured. The browser build switches to Low once if it drops below 40 FPS.
- Difficulty and random-battle settings are stored per device, not per save.
- iPhone home-screen app storage is separate from Safari: saves must be moved with Export / Import.
- Battle animations are functional but simple (tweens + frame swaps).
- Some legend tiles (rail, glass, salt) exist for future regions only.
