extends Node
## Entry point. Applies display preferences, then routes to the title screen
## (or to the automated smoke route when launched with `-- --smoke`).

func _ready() -> void:
	get_tree().root.content_scale_factor = float(Settings.get_value("ui_scale"))
	Settings.changed.connect(func(k: String) -> void:
		if k == "ui_scale":
			get_tree().root.content_scale_factor = float(Settings.get_value("ui_scale"))
		if k == "high_contrast":
			UITheme.invalidate())
	if not Content.load_errors.is_empty():
		for e in Content.load_errors:
			push_error("Content: " + e)
	await get_tree().process_frame
	# Development harnesses (tests/ is excluded from release exports).
	for arg: String in ["--smoke", "--shots"]:
		if arg in OS.get_cmdline_user_args():
			var path := "res://tests/%s.gd" % ("smoke_route" if arg == "--smoke" else "shots")
			if ResourceLoader.exists(path):
				get_tree().root.add_child(load(path).new())
				return
	Router.goto_title()
