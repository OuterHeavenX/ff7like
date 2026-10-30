extends Node
## Development-only screenshot harness: godot -- --shots --out=/abs/dir

var out := "user://shots"


func _shot(name: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("shot ", name)


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	GameState.new_game()
	for f in ["met_nessa", "toll_happened", "met_wren", "wardens_came", "garran_joined", "mira_joined", "autosave_enabled"]:
		GameState.set_flag(f)
	GameState.join_member("garran", true)
	GameState.join_member("mira", true)
	GameState.start_quest("mq_street_forgot")
	GameState.set_quest_stage("mq_street_forgot", 4)
	GameState.add_item("hi_tonic", 2)
	GameState.chapter = "ch1"
	await Router.enter_world("bellweather_square", "west")
	await _wait(3.5)
	await _shot("square")
	Router.world.player.place(Vector2i(17, 13), Router.world.grid.stand_height(17, 13))
	await _wait(1.0)
	await _shot("square_bell")
	await Router.enter_world("bellweather_wick", "default")
	await _wait(3.5)
	await _shot("wick")
	await Router.enter_world("copper_kettle", "default")
	await _wait(1.0)
	await _shot("inn")
	await Router.enter_world("undercroft_cistern", "north")
	await _wait(1.0)
	await _shot("cistern")
	await Router.enter_world("undercroft_core", "north")
	await _wait(1.0)
	await _shot("core")
	Router.world.open_menu("")
	await _wait(0.6)
	await _shot("menu_party")
	var m: Node = Router.world.menu_layer.get_child(0)
	m.section_idx = 3
	m._show_section(true)
	await _wait(0.3)
	await _shot("menu_jobs")
	m.section_idx = 5
	m._show_section(true)
	await _wait(0.3)
	await _shot("menu_journal")
	m.close()
	await _wait(0.3)
	Router.run_battle("uc_crabs", {"can_escape": true})
	await _wait(3.2)
	await _shot("battle_start")
	await _wait(3.0)
	await _shot("battle_menu")
	var b: Node = Router.battle
	if b and b._active_uid != "":
		b._choose_skill("attack")
		await _wait(0.4)
		await _shot("battle_target")
	get_tree().quit()
