class_name InventoryPanel
extends Control

const PAD := 14.0
const TITLE_H := 34.0

var tag: FurnitureTag = null
signal closed

func _ready() -> void:
	visible = false

func open(t: FurnitureTag) -> void:
	tag = t
	visible = true
	queue_redraw()

func close() -> void:
	var was_open := visible
	visible = false
	tag = null
	if was_open:
		closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _cell_px(cells: Vector2i) -> float:
	var avail_w := size.x * 0.9 - PAD * 2.0
	var avail_h := size.y * 0.9 - PAD * 2.0 - TITLE_H
	return minf(floorf(minf(avail_w / cells.x, avail_h / cells.y)), 40.0)

func _box_rect(cells: Vector2i, cp: float) -> Rect2:
	var box_size := Vector2(cells.x * cp + PAD * 2.0, cells.y * cp + PAD * 2.0 + TITLE_H)
	return Rect2((size - box_size) / 2.0, box_size)

func _close_rect(box: Rect2) -> Rect2:
	return Rect2(box.end.x - 28.0, box.position.y + 6.0, 22.0, 22.0)

func _gui_input(event: InputEvent) -> void:
	if tag == null:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			close()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var cells := tag.inventory_cells()
			var box := _box_rect(cells, _cell_px(cells))
			if _close_rect(box).has_point(event.position) or not box.has_point(event.position):
				close()

func _draw() -> void:
	if tag == null:
		return
	var cells := tag.inventory_cells()
	var cp := _cell_px(cells)
	var box := _box_rect(cells, cp)
	var gp := box.position + Vector2(PAD, PAD + TITLE_H)
	var font := ThemeDB.fallback_font
	var sub := float(tag.inventory_sub)

	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.6))
	draw_rect(box, Color(0.1, 0.1, 0.13))
	draw_rect(box, Color(0.4, 0.4, 0.5), false, 2.0)
	draw_string(font, box.position + Vector2(PAD, PAD + 14.0), tag.get_display_name(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	var cr := _close_rect(box)
	draw_rect(cr, Color(0.35, 0.15, 0.15))
	draw_string(font, cr.position + Vector2(6, 17), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

	# Big cells (alternating shade), then small cell lines, then big cell borders
	for bx in tag.inventory_big_cells.x:
		for by in tag.inventory_big_cells.y:
			var shade := Color(0.15, 0.15, 0.19) if (bx + by) % 2 == 0 else Color(0.18, 0.18, 0.23)
			draw_rect(Rect2(gp + Vector2(bx, by) * cp * sub, Vector2(cp, cp) * sub), shade)
	for x in cells.x:
		for y in cells.y:
			draw_rect(Rect2(gp + Vector2(x, y) * cp, Vector2(cp, cp)), Color(0.28, 0.28, 0.34), false, 1.0)
	for bx in tag.inventory_big_cells.x:
		for by in tag.inventory_big_cells.y:
			draw_rect(Rect2(gp + Vector2(bx, by) * cp * sub, Vector2(cp, cp) * sub), Color(0.6, 0.6, 0.7), false, 2.0)

	for entry in tag.stored:
		var t: Vector2i = entry["tile"]
		var s: Vector2i = entry["size"]
		var col: Color = entry["color"]
		var nm: String = entry["name"]
		var r := Rect2(gp + Vector2(t) * cp, Vector2(s) * cp).grow(-2.0)
		draw_rect(r, col)
		draw_string(font, r.position + Vector2(4, 14), nm,
			HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 6.0, 12, Color.WHITE)
