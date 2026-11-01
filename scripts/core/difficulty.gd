class_name Difficulty
extends RefCounted
## Player-facing challenge settings (machine-local, changeable any time in
## Settings > Gameplay). Difficulty scales enemies and XP; the random-battle
## option trades encounter frequency for bigger rewards per fight.

const LEVELS := ["story", "normal", "hard"]
const LABELS := ["Story", "Normal", "Hard"]
const BLURBS := {
	"story": "For the story first: enemies have 35% less HP and hit 30% softer; +25% XP.",
	"normal": "The intended balance. No grinding needed if you fight what you meet.",
	"hard": "Enemies have 30% more HP and hit 15% harder. Same rewards.",
}
const ENEMY_MODS := {
	"story": {"hp": 0.65, "power": 0.70},
	"normal": {"hp": 1.0, "power": 1.0},
	"hard": {"hp": 1.30, "power": 1.15},
}
const XP_MULT := {"story": 1.25, "normal": 1.0, "hard": 1.0}
## "fewer": half as many random battles, each worth double XP, JP and gold.
const ENCOUNTER_RATE := {"normal": 1.0, "fewer": 0.5}
const ENCOUNTER_REWARD := {"normal": 1.0, "fewer": 2.0}


static func level() -> String:
	var d := str(Settings.get_value("difficulty"))
	return d if d in LEVELS else "normal"


static func enemy_mods() -> Dictionary:
	return ENEMY_MODS[level()]


static func encounter_rate() -> float:
	return float(ENCOUNTER_RATE.get(str(Settings.get_value("encounters")), 1.0))


## Multipliers for a won battle's rewards. Random encounters get the
## "fewer battles" compensation; story battles do not.
static func reward_mults(random_encounter: bool) -> Dictionary:
	var enc := float(ENCOUNTER_REWARD.get(str(Settings.get_value("encounters")), 1.0)) if random_encounter else 1.0
	return {"xp": float(XP_MULT[level()]) * enc, "jp": enc, "gold": enc}


## Scales an enemy unit in place (HP, ATK, MAG). Party units are never touched.
static func apply(u: BattleUnit, mods: Dictionary) -> void:
	if u.side != 1 or mods.is_empty():
		return
	var hp_k := float(mods.get("hp", 1.0))
	var pw_k := float(mods.get("power", 1.0))
	u.max_hp = maxi(1, int(round(u.max_hp * hp_k)))
	u.hp = u.max_hp
	u.atk = maxi(1, int(round(u.atk * pw_k)))
	u.mag = maxi(1, int(round(u.mag * pw_k)))
