extends CanvasLayer

var _day_label: Button
var _money_label: Button
var _info: InfoMenu

func _ready() -> void:
	layer = 0  # below the fade and layout editor, so those cover it

	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.85)
	style.border_color = Color(0.45, 0.45, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	_info = InfoMenu.new()
	add_child(_info)

	_day_label = _make_button(Color.WHITE, "Click for the calendar")
	_money_label = _make_button(Color(0.95, 0.85, 0.35), "Click for today's finances")
	_day_label.pressed.connect(_info.toggle_calendar)
	_money_label.pressed.connect(_info.toggle_ledger)
	box.add_child(_day_label)
	box.add_child(_money_label)

	GameState.day_changed.connect(_on_day_changed)
	GameState.money_changed.connect(_on_money_changed)
	_on_day_changed(GameState.day)
	_on_money_changed(GameState.money)

func _make_button(color: Color, tip: String) -> Button:
	var b := Button.new()
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE  # so movement keys never get eaten by the button
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 20)
	for key in ["font_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, color)
	b.add_theme_color_override("font_hover_color", color.lightened(0.35))
	return b

func _on_day_changed(d: int) -> void:
	_day_label.text = "Day %d" % d

func _on_money_changed(m: int) -> void:
	_money_label.text = "§ %s" % _fmt(m)

# 1234567 -> "1,234,567"
func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			out = "," + out
		out = s[i] + out
		count += 1
	return ("-" if n < 0 else "") + out

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			GameState.add_money(25)
		elif event.keycode == KEY_F2:
			GameState.next_day()
