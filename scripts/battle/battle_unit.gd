class_name BattleUnit
extends RefCounted
## Plain battle-time combatant. Built from GameState members or enemy data;
## the simulation mutates these, never live scene nodes.

var uid: String = ""
var source_id: String = ""
var side: int = 0                 # 0 party, 1 enemies
var name: String = ""
var level: int = 1
var max_hp: int = 1
var max_sp: int = 0
var hp: int = 1
var sp: int = 0
var atk: int = 1
var mag: int = 1
var def: int = 1
var res: int = 1
var spd: int = 1
var dex: int = 1
var evade: float = 0.0
var atb: float = 0.0
var row: String = "front"
var ranged: bool = false
var element_mod: Dictionary = {}  # element -> multiplier (1.5 weak, 0.5 resist, 0 immune, -1 absorb)
var status_res: Dictionary = {}   # status -> 0..1 resist chance (1.0 = immune)
var statuses: Dictionary = {}     # status id -> {turns, power}
var tags: Array = []
var skills: Array = []
var ai: Array = []
var phases: Array = []
var phase: int = 0
var charging: Dictionary = {}     # pending charged skill {skill, targets}
var delayed: Array = []           # [{skill, targets, turns}]
var summoned: bool = false
var boss: bool = false
var role: String = ""
var rewards: Dictionary = {}
var waiting_command: bool = false
var queued: bool = false
var turns_taken: int = 0
var last_command: Dictionary = {}
var sprite: String = ""
var weapon_element: String = ""


func alive() -> bool:
	return hp > 0


func can_act() -> bool:
	return alive() and not has_status("sleep") and not has_status("stun")


func has_status(id: String) -> bool:
	return statuses.has(id)


func hp_ratio() -> float:
	return float(hp) / float(maxi(1, max_hp))


func elem(e: String) -> float:
	if e == "" or e == "physical":
		return float(element_mod.get("physical", 1.0))
	return float(element_mod.get(e, 1.0))


static func from_member(cid: String, idx: int) -> BattleUnit:
	var u := BattleUnit.new()
	var m: Dictionary = GameState.members[cid]
	var st: Dictionary = GameState.stats_for(cid)
	var c: Dictionary = Content.character(cid)
	u.uid = "p%d" % idx
	u.source_id = cid
	u.side = 0
	u.name = str(c.get("name", cid))
	u.level = int(m.level)
	u.max_hp = int(st.hp)
	u.max_sp = int(st.sp)
	u.hp = clampi(int(m.hp), 0, u.max_hp)
	u.sp = clampi(int(m.sp), 0, u.max_sp)
	u.atk = int(st.atk)
	u.mag = int(st.mag)
	u.def = int(st.def)
	u.res = int(st.res)
	u.spd = int(st.spd)
	u.dex = int(st.dex)
	u.row = str(m.get("row", "front"))
	u.ranged = bool(st.get("ranged", false))
	u.tags = st.get("tags", [])
	u.sprite = str(c.get("sprite", cid))
	for e: String in st.get("element_res", {}).keys():
		u.element_mod[e] = clampf(1.0 - float(st.element_res[e]), -1.0, 2.0)
	u.status_res = st.get("status_res", {}).duplicate()
	u.weapon_element = str(Content.item(str(m.equip.get("weapon", ""))).get("element", ""))
	return u


static func from_enemy(eid: String, idx: int) -> BattleUnit:
	var u := BattleUnit.new()
	var e: Dictionary = Content.enemy(eid)
	var s: Dictionary = e.get("stats", {})
	u.uid = "e%d" % idx
	u.source_id = eid
	u.side = 1
	u.name = str(e.get("name", eid))
	u.level = int(e.get("level", 1))
	u.max_hp = int(s.get("hp", 30))
	u.hp = u.max_hp
	u.max_sp = int(s.get("sp", 99))
	u.sp = u.max_sp
	u.atk = int(s.get("atk", 8))
	u.mag = int(s.get("mag", 8))
	u.def = int(s.get("def", 5))
	u.res = int(s.get("res", 5))
	u.spd = int(s.get("spd", 8))
	u.dex = int(s.get("dex", 8))
	u.evade = float(s.get("evade", 0.0))
	u.element_mod = e.get("elements", {}).duplicate()
	u.status_res = e.get("status_res", {}).duplicate()
	u.skills = e.get("skills", ["attack"])
	u.ai = e.get("ai", [])
	u.phases = e.get("phases", [])
	u.boss = bool(e.get("boss", false))
	u.role = str(e.get("role", ""))
	u.tags = e.get("tags", [])
	u.row = str(e.get("row", "front"))
	u.ranged = bool(e.get("ranged", false))
	u.sprite = str(e.get("sprite", eid))
	u.rewards = {"xp": int(e.get("xp", 0)), "jp": int(e.get("jp", 0)), "gold": int(e.get("gold", 0)),
		"drops": e.get("drops", [])}
	return u
