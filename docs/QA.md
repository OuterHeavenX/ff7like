# QA Log

All results below were actually run in the development container (Linux x86_64, 4 vCPU, no GPU) on 2026-10-30 unless marked otherwise.

## Automated (pass)
| Check | Command | Result |
|---|---|---|
| Content validator | `python3 tools/validate_content.py` | OK — 8 characters, 12 jobs, 158 skills, 44 items, 11 enemies, 13 encounters, 7 quests, 92 events, 12 maps |
| Script compile | `godot --headless -s res://tools/check_scripts.gd` | 0 failures |
| Unit/integration tests | `godot --headless res://tests/test_runner.tscn` | 48 passed, 0 failed (battle rules, statuses, targeting, rewards, progression, inventory, quests, saves/migration/corruption/import, content integrity incl. map reachability, balance sims) |
| Traversal harness | `godot --headless -- --smoke` | ROUTE OK — Prologue → Chapter One → Chapter Two end: all main/side/personal quests, optional elite, both bosses, Millbrook choice; real events, auto-battle, **simulated grinding (Lv10 before Ch1 boss, Lv13 before Ch2 freight)** |
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
Estimated real duration (sim time + ~1.3 s per presented action + decision time): common fights ~25–45 s, boss ~4–6 min. **Unmeasured by a human.**

## Playtime
Chapter Two estimate: 60–80 min (not measured). Prologue + Chapter One estimate: 45–60 min for a first-time player (dialogue ~92 events, ~12–18 random battles, 3 story battles, elite, boss). **Not measured.** The harness playtime figure (≈6 min at 6× speed with auto-advance) is not representative.

## Pending real-device checks (NOT done)
- [ ] iPhone Safari (landscape, touch controls, audio after tap, save persistence in Safari ITP)
- [ ] iPad Safari
- [ ] Android Chrome
- [ ] Desktop Firefox / Safari / Chrome on real GPUs; itch.io iframe embed persistence
- [ ] Steam Deck: Desktop Mode launch, Gaming Mode as non-Steam game, controller prompts, 1280×800 60 FPS measurement, suspend/resume
- [ ] Physical gamepad hotplug on desktop
- [ ] Human full playthrough of Prologue + Chapter One with timing

## Known issues
- Chapters 2–8 not built; the Map screen lists only Bellweather locations.
- Battle animations are functional but simple (tweens + frame swaps).
- Some legend tiles (rail, glass, salt) exist for future regions only.
