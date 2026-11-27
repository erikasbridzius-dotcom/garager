class_name InfoMenu
extends CanvasLayer

# The calendar and the daily finances popups, opened from the HUD's day and money labels.

const DAYS_PER_PAGE := 28
const COLS := 7

var _calendar: PanelContainer
var _ledger: PanelContainer
var _cal_title: Label
var _grid: GridContainer
var _details: Label
var _ledger_box: VBoxContainer
var _page := 0
var _selected := 1
var _editor: LayoutEditor

func _ready() -> void:
	layer = 3
	add_to_group("ui_blocker")
	_editor = get_tree().current_scene.find_child("ShopEditor", true, false) as LayoutEditor
	_build_calendar()
	_build_ledger()
	_calendar.visible = false
	_ledger.visible = false
	GameState.money_changed.connect(func(_m): _refresh_open())
	GameState.day_changed.connect(func(_d): _refresh_open())

func _process(_delta: float) -> void:
	if _editor != null and _editor.editing and (_calendar.visible or _ledger.visible):
		_hide_all()

func blocks_point(p: Vector2) -> bool:
	return (_calendar.visible and _calendar.get_global_rect().has_point(p)) \
		or (_ledger.visible and _ledger.get_global_rect().has_point(p))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if _calendar.visible or _ledger.visible:
			_hide_all()
			get_viewport().set_input_as_handled()

# ---------- opening and closing ----------

func toggle_calendar() -> void:
	var show := not _calendar.visible
	_hide_all()
	if show:
		_page = floori((GameState.day - 1) / float(DAYS_PER_PAGE))
		_selected = GameState.day
		_refresh_calendar()
		_calendar.visible = true

func toggle_ledger() -> void:
	var show := not _ledger.visible
	_hide_all()
	if show:
		_refresh_ledger()
		_ledger.visible = true

func _hide_all() -> void:
	_calendar.visible = false
	_ledger.visible = false

func _refresh_open() -> void:
	if _calendar.visible:
		_refresh_calendar()
	if _ledger.visible:
		_refresh_ledger()

# ---------- building ----------

func _make_panel() -> PanelContainer:
	var p := PanelContainer.new()
	p.position = Vector2(16, 70)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.96)
	style.border_color = Color(0.45, 0.45, 0.55)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", style)
	add_child(p)
	return p

func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b

func _build_calendar() -> void:
	_calendar = _make_panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_calendar.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	head.add_child(_button("<", _flip.bind(-1)))
	_cal_title = Label.new()
	_cal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cal_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_cal_title)
	head.add_child(_button(">", _flip.bind(1)))
	head.add_child(_button("X", _hide_all))

	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 3)
	_grid.add_theme_constant_override("v_separation", 3)
	box.add_child(_grid)

	_details = Label.new()
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_details.custom_minimum_size = Vector2(298, 0)
	box.add_child(_details)

	var legend := Label.new()
	legend.text = "Gold = today   Orange edge / § = rent   • = event"
	legend.add_theme_font_size_override("font_size", 11)
	legend.add_theme_color_override("font_color", Color(0.6, 0.62, 0.7))
	box.add_child(legend)

func _build_ledger() -> void:
	_ledger = _make_panel()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_ledger.add_child(box)

	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.text = "Finances"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_button("X", _hide_all))

	_ledger_box = VBoxContainer.new()
	_ledger_box.custom_minimum_size = Vector2(250, 0)
	_ledger_box.add_theme_constant_override("separation", 4)
	box.add_child(_ledger_box)

# ---------- calendar ----------

func _flip(dir: int) -> void:
	_page = maxi(0, _page + dir)
	_refresh_calendar()

func _select(d: int) -> void:
	_selected = d
	_refresh_calendar()

func _refresh_calendar() -> void:
	var first := _page * DAYS_PER_PAGE + 1
	_cal_title.text = "Days %d - %d" % [first, first + DAYS_PER_PAGE - 1]
	for c in _grid.get_children():
		_grid.remove_child(c)
		c.queue_free()
	for i in DAYS_PER_PAGE:
		_grid.add_child(_day_button(first + i))
	_details.text = _details_text(_selected)

func _cell_style(bg: Color, border: Color, width: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(width)
	s.set_corner_radius_all(3)
	return s

func _day_button(d: int) -> Button:
	var events: Array = GameState.event_log.get(d, [])
	var rent := GameState.rent_on(d)
	var mark := ""
	if rent > 0:
		mark += "§"
	if not events.is_empty():
		mark += "•"

	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(40, 38)
	b.add_theme_font_size_override("font_size", 14)
	b.text = "%d\n%s" % [d, mark]

	var bg := Color(0.14, 0.14, 0.18)
	if not events.is_empty():
		bg = Color(0.17, 0.2, 0.3)
	var border := Color(0.3, 0.3, 0.38)
	var width := 1
	if rent > 0:
		border = Color(0.95, 0.55, 0.2)
		width = 2
	var font := Color.WHITE if d <= GameState.day else Color(0.6, 0.6, 0.68)
	if d == GameState.day:
		bg = Color(0.9, 0.75, 0.2)
		font = Color.BLACK
	if d == _selected:
		border = Color.WHITE
		width = 2

	var style := _cell_style(bg, border, width)
	for state in ["normal", "hover", "pressed", "focus"]:
		b.add_theme_stylebox_override(state, style)
	for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(key, font)
	b.pressed.connect(_select.bind(d))
	return b

func _details_text(d: int) -> String:
	var lines: Array[String] = []
	lines.append("Day %d%s" % [d, " (today)" if d == GameState.day else ""])
	if d <= GameState.day:
		var events: Array = GameState.event_log.get(d, [])
		if events.is_empty():
			lines.append("No events.")
		for e in events:
			lines.append("%s: %s" % [e["title"], e["text"]])
	else:
		lines.append("Events: not known yet.")
	var rent := GameState.rent_on(d)
	if rent > 0:
		if d <= GameState.day:
			lines.append("Rent paid: § %d" % rent)
		else:
			lines.append("Rent due: § %d" % rent)
	return "\n".join(PackedStringArray(lines))

# ---------- finances ----------

func _line(text: String, color: Color, font_size := 16) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	_ledger_box.add_child(l)

func _refresh_ledger() -> void:
	for c in _ledger_box.get_children():
		_ledger_box.remove_child(c)
		c.queue_free()
	var white := Color.WHITE
	var gold := Color(0.95, 0.85, 0.35)
	var green := Color(0.6, 0.9, 0.6)
	var red := Color(1.0, 0.55, 0.5)
	var orange := Color(1.0, 0.7, 0.4)
	var grey := Color(0.7, 0.72, 0.8)

	_line("Day %d" % GameState.day, white, 18)
	_line("Balance: § %d" % GameState.money, gold)
	_line("Made today: + § %d" % GameState.earned_today, green)
	_line("Spent today: - § %d" % GameState.spent_today, red)
	if GameState.rent_paid_today > 0:
		_line("Rent paid today: - § %d" % GameState.rent_paid_today, red)
	var net := GameState.earned_today - GameState.spent_today - GameState.rent_paid_today
	_line("Net today: %s§ %d" % ["+" if net >= 0 else "-", absi(net)], white)
	_line("- - - - - - - - - - - -", grey, 12)
	_line("Rent: § %d" % GameState.rent, orange)
	_line("Due on day %d (in %d days)" % [GameState.next_rent_day, GameState.next_rent_day - GameState.day], grey)
	var next_amount := ceili(GameState.rent * (1.0 + GameState.RENT_GROWTH))
	_line("Next time: § %d (+%d%%)" % [next_amount, roundi(GameState.RENT_GROWTH * 100.0)], grey)
