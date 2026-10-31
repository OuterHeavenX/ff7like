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
	if OS.has_feature("web"):
		_install_web_audio_unlock()
	await get_tree().process_frame
	# Development harnesses (tests/ is excluded from release exports).
	var harnesses := {"--smoke": "smoke_route", "--shots": "shots", "--padtest": "padtest"}
	for arg: String in harnesses.keys():
		if arg in OS.get_cmdline_user_args():
			var path := "res://tests/%s.gd" % harnesses[arg]
			if ResourceLoader.exists(path):
				get_tree().root.add_child(load(path).new())
				return
	Router.goto_title()


## iOS Safari mutes Web Audio while the ringer/silent switch is on. On the
## first real user gesture (inside the DOM event handler, which iOS requires),
## ask for a "playback" audio session (Safari 17+) and start a silent looping
## media element (older iOS) so the game's audio plays like a video would.
func _install_web_audio_unlock() -> void:
	JavaScriptBridge.eval("""
		(function () {
			if (window.__echoesAudioUnlock) { return; }
			window.__echoesAudioUnlock = true;
			var silent = 'data:audio/wav;base64,UklGRvQHAABXQVZFZm10IBAAAAABAAEAQB8AAEAfAAABAAgAZGF0YdAHAACAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgICAgA==';
			function unlock() {
				try { if (navigator.audioSession) { navigator.audioSession.type = 'playback'; } } catch (e) {}
				try {
					var a = document.createElement('audio');
					a.setAttribute('playsinline', '');
					a.setAttribute('x-webkit-airplay', 'deny');
					a.loop = true;
					a.src = silent;
					a.volume = 0.01;
					var p = a.play();
					if (p && p.catch) { p.catch(function () {}); }
					window.__echoesSilentAudio = a;
				} catch (e) {}
				['touchend', 'click', 'keydown'].forEach(function (t) {
					document.removeEventListener(t, unlock, true);
				});
			}
			['touchend', 'click', 'keydown'].forEach(function (t) {
				document.addEventListener(t, unlock, true);
			});
		})();
	""", true)
