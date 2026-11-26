class_name DayCard
extends CanvasLayer

# The black screen between days: "Day 2" plus the day's events.

var _rect: ColorRect
var _title: Label
var _events: VBoxContainer

func _ready() -> void:
	layer = 50
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks clicks while it is up
	_rect.visible = false
	add_child(_rect)

	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 44)
	box.add_child(_title)

	_events = VBoxContainer.new()
	_events.add_theme_constant_override("separation", 8)
	_events.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_events)

func show_day(day: int, events: Array) -> void:
	_title.text = "Day %d" % day
	for c in _events.get_children():
		_events.remove_child(c)
		c.queue_free()
	for e in events:
		var l := Label.new()
		l.text = "%s\n%s" % [e["title"], e["text"]]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 16)
		var up := float(e["mult"]) > 1.0
		l.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4) if up else Color(0.6, 0.9, 0.6))
		_events.add_child(l)
	_rect.modulate.a = 0.0
	_rect.visible = true
	var t := create_tween()
	t.tween_property(_rect, "modulate:a", 1.0, 0.5)
	await t.finished
	await get_tree().create_timer(1.4 + 1.0 * events.size()).timeout
	var t2 := create_tween()
	t2.tween_property(_rect, "modulate:a", 0.0, 0.5)
	await t2.finished
	_rect.visible = false
