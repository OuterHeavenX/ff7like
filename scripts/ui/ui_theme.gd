class_name UITheme
extends RefCounted
## Builds the shared UI theme in code (fonts, panels, buttons, focus states).
## Regenerated when contrast settings change.

const C_BG := Color(0.055, 0.06, 0.12, 0.94)
const C_BG2 := Color(0.09, 0.10, 0.18, 0.96)
const C_BORDER := Color(0.80, 0.66, 0.40)
const C_TEXT := Color(0.95, 0.92, 0.84)
const C_DIM := Color(0.66, 0.66, 0.74)
const C_ACCENT := Color(1.0, 0.74, 0.36)
const C_FOCUS := Color(0.98, 0.70, 0.30, 0.30)
const C_HP := Color(0.36, 0.86, 0.50)
const C_SP := Color(0.42, 0.66, 1.0)
const C_ATB := Color(1.0, 0.82, 0.38)
const C_BAD := Color(1.0, 0.42, 0.40)

static var _theme: Theme = null
static var _font: Font = null
static var _bold: Font = null


static func font() -> Font:
	if _font == null:
		_font = load("res://assets/fonts/PixelifySans-Regular.woff2")
	return _font


static func bold() -> Font:
	if _bold == null:
		_bold = load("res://assets/fonts/PixelifySans-Bold.woff2")
	return _bold


static func invalidate() -> void:
	_theme = null


static func box(bg: Color, border: Color, bw: int = 2, radius: int = 4, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad + 2
	s.content_margin_right = pad + 2
	s.content_margin_top = pad
	s.content_margin_bottom = pad
	s.anti_aliasing = false
	return s


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var hc := bool(Settings.get_value("high_contrast"))
	var bg := Color(0, 0, 0, 1) if hc else C_BG
	var border := Color(1, 1, 1) if hc else C_BORDER
	var text := Color(1, 1, 1) if hc else C_TEXT
	var accent := Color(1, 1, 0) if hc else C_ACCENT
	var t := Theme.new()
	t.default_font = font()
	t.default_font_size = 22
	t.set_stylebox("panel", "PanelContainer", box(bg, border))
	t.set_stylebox("panel", "Panel", box(bg, border))
	t.set_color("font_color", "Label", text)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.9))
	t.set_constant("outline_size", "Label", 0)
	t.set_color("default_color", "RichTextLabel", text)
	t.set_font("bold_font", "RichTextLabel", bold())
	t.set_font_size("normal_font_size", "RichTextLabel", 22)
	t.set_font_size("bold_font_size", "RichTextLabel", 22)
	var btn_normal := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 6)
	var btn_hover := box(Color(accent.r, accent.g, accent.b, 0.16), Color(accent.r, accent.g, accent.b, 0.4), 1, 3, 6)
	var btn_focus := box(Color(accent.r, accent.g, accent.b, 0.26), accent, 2, 3, 6)
	var btn_pressed := box(Color(accent.r, accent.g, accent.b, 0.40), accent, 2, 3, 6)
	var btn_disabled := box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 3, 6)
	for cls: String in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", cls, btn_normal)
		t.set_stylebox("hover", cls, btn_hover)
		t.set_stylebox("focus", cls, btn_focus)
		t.set_stylebox("pressed", cls, btn_pressed)
		t.set_stylebox("hover_pressed", cls, btn_pressed)
		t.set_stylebox("disabled", cls, btn_disabled)
		t.set_color("font_color", cls, text)
		t.set_color("font_hover_color", cls, Color(1, 1, 1))
		t.set_color("font_focus_color", cls, Color(1, 1, 1))
		t.set_color("font_pressed_color", cls, Color(1, 1, 1))
		t.set_color("font_disabled_color", cls, Color(0.5, 0.5, 0.56))
		t.set_font_size("font_size", cls, 22)
	t.set_constant("h_separation", "Button", 8)
	var sb_bg := box(Color(0, 0, 0, 0.5), Color(0, 0, 0, 0), 0, 2, 0)
	var sb_fill := box(accent, Color(0, 0, 0, 0), 0, 2, 0)
	t.set_stylebox("background", "ProgressBar", sb_bg)
	t.set_stylebox("fill", "ProgressBar", sb_fill)
	t.set_font_size("font_size", "ProgressBar", 12)
	t.set_stylebox("slider", "HSlider", box(Color(1, 1, 1, 0.15), Color(0, 0, 0, 0), 0, 2, 3))
	t.set_stylebox("grabber_area", "HSlider", box(accent * Color(1, 1, 1, 0.6), Color(0, 0, 0, 0), 0, 2, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(accent, Color(0, 0, 0, 0), 0, 2, 3))
	t.set_stylebox("focus", "HSlider", box(Color(0, 0, 0, 0), accent, 2, 3, 2))
	t.set_stylebox("panel", "TabContainer", box(bg, border))
	t.set_stylebox("tab_selected", "TabBar", box(Color(accent.r, accent.g, accent.b, 0.35), accent, 2, 3, 6))
	t.set_stylebox("tab_unselected", "TabBar", box(Color(0, 0, 0, 0.3), Color(0, 0, 0, 0), 0, 3, 6))
	t.set_stylebox("tab_hovered", "TabBar", box(Color(accent.r, accent.g, accent.b, 0.2), Color(0, 0, 0, 0), 0, 3, 6))
	t.set_stylebox("tab_focus", "TabBar", box(Color(0, 0, 0, 0), accent, 2, 3, 6))
	t.set_stylebox("panel", "PopupMenu", box(bg, border))
	t.set_stylebox("normal", "LineEdit", box(Color(0, 0, 0, 0.5), border, 1, 3, 6))
	t.set_stylebox("focus", "LineEdit", box(Color(0, 0, 0, 0.5), accent, 2, 3, 6))
	var scroll := box(Color(1, 1, 1, 0.06), Color(0, 0, 0, 0), 0, 3, 0)
	var grab := box(Color(accent.r, accent.g, accent.b, 0.6), Color(0, 0, 0, 0), 0, 3, 0)
	t.set_stylebox("scroll", "VScrollBar", scroll)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	_theme = t
	return t


static func label(text: String, size: int = 22, color: Color = Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	if size != 22:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	return l


static func title_label(text: String, size: int = 28) -> Label:
	var l := label(text, size, C_ACCENT if not bool(Settings.get_value("high_contrast")) else Color(1, 1, 0))
	l.add_theme_font_override("font", bold())
	return l


static func button(text: String, cb: Callable = Callable(), min_h: int = 44) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, min_h)
	b.focus_mode = Control.FOCUS_ALL
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	if cb.is_valid():
		b.pressed.connect(cb)
	b.pressed.connect(func() -> void: Audio.sfx("confirm"))
	b.focus_entered.connect(func() -> void: Audio.sfx("cursor", 1.0))
	return b


static func bar(color: Color, h: int = 8) -> ProgressBar:
	var p := ProgressBar.new()
	p.show_percentage = false
	p.custom_minimum_size = Vector2(60, h)
	p.add_theme_stylebox_override("fill", box(color, Color(0, 0, 0, 0), 0, 2, 0))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


static func panel(pad: int = 10) -> PanelContainer:
	var p := PanelContainer.new()
	if pad != 10:
		var hc := bool(Settings.get_value("high_contrast"))
		p.add_theme_stylebox_override("panel", box(Color(0, 0, 0, 1) if hc else C_BG, Color(1, 1, 1) if hc else C_BORDER, 2, 4, pad))
	return p
