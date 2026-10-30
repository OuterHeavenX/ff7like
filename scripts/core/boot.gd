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
	if "--smoke" in OS.get_cmdline_user_args():
		var s: Node = load("res://tests/smoke_route.gd").new()
		get_tree().root.add_child(s)
		return
	Router.goto_title()
