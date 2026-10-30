#!/usr/bin/env python3
"""Fast, engine-free content validator. Exit code 1 on any error.

Checks: JSON parse, duplicate IDs, dangling references between tables, map row
geometry, trigger/NPC/party-talk event references, exit destinations + spawns,
encounter tables, shop stock, quest stage references in events, speaker IDs,
asset files for sprites/portraits/music, and unique chest IDs.
The in-engine suite (tests/test_content.gd) additionally checks walkability and
reachability using the real MapGrid rules.
"""
import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C = os.path.join(ROOT, "content")
errors = []


def err(msg):
    errors.append(msg)


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:  # noqa: BLE001
        err(f"{os.path.relpath(path, ROOT)}: {e}")
        return None


def table(name):
    data = load(os.path.join(C, name + ".json")) or []
    out = {}
    for e in data:
        if e["id"] in out:
            err(f"duplicate id {e['id']} in {name}")
        out[e["id"]] = e
    return out


T = {n: table(n) for n in ["characters", "jobs", "skills", "items", "enemies", "encounters", "quests", "shops", "statuses", "chapters", "npcs"]}
events = {}
for fname in load(os.path.join(C, "events", "index.json")) or []:
    for k, v in (load(os.path.join(C, "events", fname + ".json")) or {}).items():
        if k in events:
            err(f"duplicate event {k}")
        events[k] = v
maps = {}
for mid in load(os.path.join(C, "maps", "index.json")) or []:
    m = load(os.path.join(C, "maps", mid + ".json"))
    if m is not None:
        maps[mid] = m


def asset(path):
    if not os.path.exists(os.path.join(ROOT, path)):
        err(f"missing asset {path}")


for sid, s in T["skills"].items():
    for op in s.get("ops", []):
        if op.get("op") == "delay" and op["skill"] not in T["skills"]:
            err(f"skill {sid} delays unknown {op['skill']}")
        if op.get("op") == "summon" and op["enemy"] not in T["enemies"]:
            err(f"skill {sid} summons unknown {op['enemy']}")
        if op.get("op") == "status" and op["id"] not in T["statuses"]:
            err(f"skill {sid} unknown status {op['id']}")
for jid, j in T["jobs"].items():
    for a in j["abilities"]:
        if a["id"] not in T["skills"]:
            err(f"job {jid} ability {a['id']} missing")
for cid, c in T["characters"].items():
    for s in c.get("personal_skills", []) + c.get("innate_skills", []):
        if s not in T["skills"]:
            err(f"character {cid} skill {s} missing")
    if c["default_job"] not in T["jobs"]:
        err(f"character {cid} job missing")
    asset(f"assets/sprites/chars/{c['sprite']}_field.png")
    asset(f"assets/portraits/{c['sprite']}_neutral.png")
for eid, e in T["enemies"].items():
    for r in e.get("ai", []) + [r for ph in e.get("phases", []) for r in ph.get("ai", [])]:
        if r["skill"] not in T["skills"]:
            err(f"enemy {eid} ai skill {r['skill']} missing")
    for d in e.get("drops", []):
        if d["item"] not in T["items"]:
            err(f"enemy {eid} drop {d['item']} missing")
    asset(f"assets/sprites/enemies/{e.get('sprite', eid)}.png")
for enc, e in T["encounters"].items():
    for x in e["enemies"]:
        if x not in T["enemies"]:
            err(f"encounter {enc} enemy {x} missing")
    if e.get("arena") not in maps:
        err(f"encounter {enc} arena {e.get('arena')} missing")
for sh, s in T["shops"].items():
    for i in s["items"]:
        if i not in T["items"] or T["items"][i].get("price", 0) <= 0:
            err(f"shop {sh} item {i} missing or unpriced")


def walk_cmds(eid, cmds):
    for c in cmds:
        if "item" in c and c["item"] not in T["items"]:
            err(f"event {eid} item {c['item']}")
        for key in ("quest_start", "quest_complete"):
            if key in c and c[key] not in T["quests"]:
                err(f"event {eid} {key} {c[key]}")
        if "quest_stage" in c:
            q = T["quests"].get(c["quest_stage"][0])
            if not q or c["quest_stage"][1] >= len(q["stages"]):
                err(f"event {eid} quest_stage {c['quest_stage']}")
        if "battle" in c and c["battle"] not in T["encounters"]:
            err(f"event {eid} battle {c['battle']}")
        if "warp" in c and c["warp"] not in maps:
            err(f"event {eid} warp {c['warp']}")
        if "call" in c and c["call"] not in events:
            err(f"event {eid} call {c['call']}")
        if "shop" in c and c["shop"] not in T["shops"]:
            err(f"event {eid} shop {c['shop']}")
        if "say" in c and c["say"] and c["say"] not in T["characters"] and c["say"] not in T["npcs"]:
            err(f"event {eid} unknown speaker {c['say']}")
        if "music" in c:
            asset(f"assets/audio/music/{c['music']}.ogg")
        for sub in ("then", "else", "win", "lose"):
            walk_cmds(eid, c.get(sub, []))
        for o in c.get("choice", []):
            walk_cmds(eid, o.get("do", []))


for eid, ev in events.items():
    walk_cmds(eid, ev if isinstance(ev, list) else ev.get("cmds", []))
    if isinstance(ev, dict) and ev.get("skippable") and not ev.get("recap"):
        err(f"event {eid} skippable without recap")

chests = set()
for mid, m in maps.items():
    rows = m.get("rows", [])
    w = max(len(r) for r in rows) if rows else 0
    for i, r in enumerate(rows):
        if len(r) != w:
            err(f"map {mid} row {i} width {len(r)} != {w}")
    if "heights" in m and len(m["heights"]) != len(rows):
        err(f"map {mid} heights row count mismatch")
    if mid.startswith("arena_"):
        continue
    for t in m.get("triggers", []):
        if t.get("kind") == "exit":
            dest = maps.get(t["to"])
            if not dest:
                err(f"map {mid} exit to missing {t['to']}")
            elif t.get("spawn") and t["spawn"] not in dest.get("spawns", {}):
                err(f"map {mid} exit spawn {t['to']}/{t['spawn']} missing")
        elif "event" in t and t["event"] not in events:
            err(f"map {mid} trigger event {t['event']} missing")
    for n in m.get("npcs", []):
        talk = n.get("talk", "")
        for e in (talk if isinstance(talk, list) else ([{"event": talk}] if talk else [])):
            if e["event"] not in events:
                err(f"map {mid} npc {n['id']} event {e['event']} missing")
        asset(f"assets/sprites/chars/{n.get('sprite')}_field.png")
    for p in m.get("party_talk", []):
        if p["event"] not in events:
            err(f"map {mid} party_talk {p['event']} missing")
    for e in m.get("encounters", {}).get("table", []):
        if e["enc"] not in T["encounters"]:
            err(f"map {mid} encounter {e['enc']} missing")
    for ch in m.get("chests", []):
        if ch["id"] in chests:
            err(f"duplicate chest id {ch['id']}")
        chests.add(ch["id"])
        for i in ch.get("items", {}):
            if i not in T["items"]:
                err(f"chest {ch['id']} item {i}")

counts = {k: len(v) for k, v in T.items()}
counts["events"] = len(events)
counts["maps"] = len(maps)
print("content:", ", ".join(f"{k}={v}" for k, v in counts.items()))
if errors:
    for e in errors:
        print("ERROR:", e)
    print(f"{len(errors)} error(s)")
    sys.exit(1)
print("content OK")
