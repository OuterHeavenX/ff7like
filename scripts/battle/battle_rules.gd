class_name BattleRules
extends RefCounted
## Centralized, bounded and explainable combat math. All randomness goes
## through the caller's seeded RandomNumberGenerator.
##
## Physical damage = power% x ATK x 1.5 x (1 - DEF/(DEF + 40 + 4*attacker level))
## Magic damage    = power% x MAG x 1.5 x (1 - RES/(RES + 40 + 4*attacker level))
## then x element (weak 1.5 / resist 0.5 / immune 0 / absorb heals), x0.92-1.08 variance,
## x1.6 critical, x0.6 back-row melee dealt, x0.7 back-row physical taken,
## x0.5 Guard, x0.67 Barrier, x1.3 Vulnerable. Minimum 1 (unless immune).

const CRIT_MULT := 1.6
const BACK_ROW_DEALT := 0.6
const BACK_ROW_TAKEN := 0.7
const GUARD_MULT := 0.5
const BARRIER_MULT := 0.67
const VULN_MULT := 1.3
const BURN_ATK := 0.85

## Duration units are the affected unit's own turns. Statuses never tick while
## time is paused for menus because they only advance when that unit acts.
const STATUS_DEFAULT_TURNS := {
	"poison": 4, "burn": 3, "slow": 3, "haste": 3, "sleep": 3, "silence": 3, "blind": 3,
	"regen": 4, "barrier": 3, "stun": 1, "vulnerable": 3, "mark": 3, "guard": 1, "cover": 3,
}
const BAD := ["poison", "burn", "slow", "sleep", "silence", "blind", "stun", "vulnerable", "mark"]
const GOOD := ["haste", "regen", "barrier", "guard", "cover"]


static func mitigation(defense: int, attacker_level: int) -> float:
	return float(defense) / float(defense + 40 + 4 * attacker_level)


static func atk_stat(u: BattleUnit) -> float:
	var a := float(u.atk)
	if u.has_status("burn"):
		a *= BURN_ATK
	return a


static func base_damage(attacker: BattleUnit, target: BattleUnit, op: Dictionary) -> float:
	var physical := str(op.get("type", "physical")) == "physical"
	var power := float(op.get("power", 100)) / 100.0
	var stat := atk_stat(attacker) if physical else float(attacker.mag)
	var d := float(target.def if physical else target.res)
	d *= (1.0 - float(op.get("pierce", 0.0)))
	return power * stat * 1.5 * (1.0 - mitigation(int(d), attacker.level))


static func hit_chance(attacker: BattleUnit, target: BattleUnit, op: Dictionary) -> float:
	if str(op.get("type", "physical")) != "physical":
		return float(op.get("accuracy", 1.0))
	var c := float(op.get("accuracy", 1.0)) - target.evade
	if attacker.has_status("blind"):
		c *= 0.5
	if target.has_status("sleep") or target.has_status("stun"):
		c = 1.0
	return clampf(c, 0.05, 1.0)


static func crit_chance(attacker: BattleUnit, target: BattleUnit, op: Dictionary) -> float:
	if str(op.get("type", "physical")) != "physical":
		return 0.0
	var c := 0.05 + float(attacker.dex) / float(attacker.dex + 200) * 0.2 + float(op.get("crit_bonus", 0.0))
	if target.has_status("mark"):
		c += 0.2
	if "critical_up" in attacker.tags:
		c += 0.1
	return clampf(c, 0.0, 0.75)


## Computes damage for one hit. Returns {amount, crit, miss, element_mult}.
static func roll_damage(rng: RandomNumberGenerator, attacker: BattleUnit, target: BattleUnit, op: Dictionary, melee: bool) -> Dictionary:
	if rng.randf() > hit_chance(attacker, target, op):
		return {"amount": 0, "miss": true, "crit": false, "element_mult": 1.0}
	var physical := str(op.get("type", "physical")) == "physical"
	var element := str(op.get("element", ""))
	if element == "" and physical:
		element = attacker.weapon_element
	var em := target.elem(element)
	var dmg := float(op.fixed) if op.has("fixed") else base_damage(attacker, target, op)
	dmg *= rng.randf_range(0.92, 1.08)
	var crit := rng.randf() < crit_chance(attacker, target, op)
	if crit:
		dmg *= CRIT_MULT
	if physical and melee and attacker.row == "back" and not attacker.ranged:
		dmg *= BACK_ROW_DEALT
	if physical and target.row == "back" and not op.get("ignore_row", false):
		dmg *= BACK_ROW_TAKEN
	if target.has_status("guard"):
		dmg *= GUARD_MULT
	if target.has_status("barrier"):
		dmg *= BARRIER_MULT
	if target.has_status("vulnerable"):
		dmg *= VULN_MULT
	for st: String in op.get("bonus_vs", {}).keys():
		if target.has_status(st):
			dmg *= float(op.bonus_vs[st])
	if em == 0.0:
		return {"amount": 0, "miss": false, "crit": false, "element_mult": 0.0, "immune": true}
	var amount := int(round(dmg * absf(em)))
	amount = maxi(1, amount)
	if em < 0.0:
		amount = -amount   # absorbed: heals the target
	return {"amount": amount, "miss": false, "crit": crit, "element_mult": em}


static func heal_amount(rng: RandomNumberGenerator, caster: BattleUnit, target: BattleUnit, op: Dictionary) -> int:
	var amt := 0.0
	if op.has("pct"):
		amt += float(target.max_hp) * float(op.pct)
	if op.has("power"):
		amt += float(op.power) / 100.0 * float(caster.mag) * 2.0 + float(op.get("flat", 0))
	if op.has("flat") and not op.has("power"):
		amt += float(op.flat)
	if "item_boost" in caster.tags and op.get("item", false):
		amt *= 1.5
	if target.has_status("burn"):
		amt *= 0.75
	return maxi(1, int(round(amt * rng.randf_range(0.95, 1.05))))


## Status application with resistances. Bosses may resist; immunity is explicit.
static func status_lands(rng: RandomNumberGenerator, target: BattleUnit, status: String, chance: float) -> bool:
	if not target.alive():
		return false
	var resist := float(target.status_res.get(status, 0.0))
	if resist >= 1.0:
		return false
	if status == "stun" and target.has_status("stun_guard"):
		return false
	if status == "sleep" and target.has_status("sleep_guard"):
		return false
	return rng.randf() < chance * (1.0 - resist)


static func atb_rate(u: BattleUnit) -> float:
	## ATB points per second at battle speed 1.0 (100 points = a turn).
	var r := 100.0 / 3.2 * (float(u.spd) + 30.0) / 42.0
	if u.has_status("haste"):
		r *= 1.5
	if u.has_status("slow"):
		r *= 0.6
	return r


static func escape_chance(party_spd: float, enemy_spd: float, attempts: int) -> float:
	return clampf(0.55 + (party_spd - enemy_spd) / 40.0 + 0.15 * attempts, 0.25, 0.95)
