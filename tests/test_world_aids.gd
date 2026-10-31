extends RefCounted
## Navigation aids (objective resolution, routing) and 3D character models.

var t: Node


## Every non-final stage of every quest must point somewhere on the map, so the
## objective marker never goes silent mid-quest.
func test_every_quest_stage_has_a_target() -> void:
	for qid: String in Content.table("quests").keys():
		var stages: Array = Content.quest(qid).get("stages", [])
		for s in maxi(0, stages.size() - 1):
			GameState.quests[qid] = {"stage": s, "done": false, "outcome": "", "failed": false}
			t.ok(not Nav.objective_locations(qid).is_empty(), "%s stage %d has no objective location" % [qid, s])
		GameState.quests.erase(qid)


## Objective targets must be reachable through exits from where the previous
## stage's target was (or the quest's own map), ignoring exit conditions.
func test_objective_maps_exist_and_route() -> void:
	GameState.new_game()
	GameState.start_quest("mq_sealed_fork")
	var r := Nav.resolve("mq_sealed_fork", "bellweather_wick")
	t.ok(not r.is_empty(), "prologue objective resolves from Wick Street")
	t.eq(str(r.get("map", "")), "post_office", "first prologue objective is the Post Office")
	t.eq(str((r.get("exit", {}) as Dictionary).get("to", "")), "bellweather_square", "route goes via Lantern Square")


func test_route_through_scripted_passage() -> void:
	GameState.new_game()
	var route := Nav.route_first_exit("bellweather_wick", "undercroft_upper")
	t.ok(not route.is_empty(), "the canal hatch counts as a passage to the Undercroft")


func test_char_models_build_for_every_spec() -> void:
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/appearance.json"))
	t.ok(d is Dictionary and (d as Dictionary).has("characters"), "appearance.json present")
	for id: String in (d as Dictionary).characters.keys():
		var m := CharModel.new()
		m.build(id, true)
		t.ok(m.head != null and m.arm_r != null and m.leg_l != null, "%s model has head, arms, legs" % id)
		t.ok(ResourceLoader.exists("res://assets/models/faces/%s.png" % id), "%s face texture exists" % id)
		for p: int in range(CharModel.Pose.size()):
			m.frame = p
			m.animate(0.05, p == 0, 4.5)
		m.free()


func test_every_character_sprite_has_a_model() -> void:
	for cid: String in Content.table("characters").keys():
		var spr := str(Content.character(cid).get("sprite", cid))
		t.ok(CharModel.has_spec(spr), "character %s (%s) has a 3D appearance spec" % [cid, spr])
