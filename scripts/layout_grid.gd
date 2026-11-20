class_name LayoutGrid
extends Control

class Item:
	var tag: FurnitureTag
	var tile := Vector2i.ZERO
	var size := Vector2i.ONE

	func rect() -> Rect2i:
		return Rect2i(tile, size)

signal item_moved(item: Item)
signal item_rotated(item: Item, step: int)
signal item_clicked(item: Item)
var _drag_moved := false

const GRID_W := 24
const GRID_H := 8

var items: Array[Item] = []
var selected: Item = null
var hovered: Item = null
var _mouse_pos := Vector2.ZERO
var _drag_item: Item = null
var _grab_offset := Vector2i.ZERO
var forbidden: Array[Rect2i] = []
var _drag_start_tile := Vector2i.ZERO
var _drag_start_size := Vector2i.ONE
var _drag_rot_delta := 0

func clear_items() -> void:
	items.clear()
	selected = null
	_drag_item = null
	hovered = null

func add_item(tag: FurnitureTag, tile: Vector2i, item_size: Vector2i) -> void:
	var it := Item.new()
	it.tag = tag
	it.tile = tile
	it.size = item_size
	items.append(it)

func _cell_px() -> float:
	return minf(size.x * 0.9 / GRID_W, size.y * 0.9 / GRID_H)

func _origin_px() -> Vector2:
	return (size - Vector2(GRID_W, GRID_H) * _cell_px()) / 2.0

func _mouse_to_tile(pos: Vector2) -> Vector2i:
	var p := (pos - _origin_px()) / _cell_px()
	return Vector2i(floori(p.x), floori(p.y))

func _item_at(cell: Vector2i) -> Item:
	for i in range(items.size() - 1, -1, -1):
		var it: Item = items[i]
		if it.tag.movable and it.rect().has_point(cell):
			return it
	return null

func _any_item_at(cell: Vector2i) -> Item:
	for i in range(items.size() - 1, -1, -1):
		var it: Item = items[i]
		if it.rect().has_point(cell):
			return it
	return null

func _update_hover() -> void:
	_mouse_pos = get_local_mouse_position()
	var old := hovered
	if _drag_item != null:
		hovered = _drag_item
	else:
		hovered = _any_item_at(_mouse_to_tile(_mouse_pos))
	if hovered != old or hovered != null:
		queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		hovered = null
		queue_redraw()

func _draw_label(text: String) -> void:
	var font := ThemeDB.fallback_font
	var fs := 16
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pad := Vector2(8, 4)
	var box := ts + pad * 2.0
	var pos := _mouse_pos + Vector2(16, 20)
	pos.x = clampf(pos.x, 0.0, size.x - box.x)
	pos.y = clampf(pos.y, 0.0, size.y - box.y)
	draw_rect(Rect2(pos, box), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(pos, box), Color(1, 1, 1, 0.4), false, 1.0)
	draw_string(font, pos + pad + Vector2(0, font.get_ascent(fs)), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)

func _can_place(it: Item, tile: Vector2i, item_size: Vector2i) -> bool:
	if tile.x < 0 or tile.y < 0 or tile.x + item_size.x > GRID_W or tile.y + item_size.y > GRID_H:
		return false
	var r := Rect2i(tile, item_size)
	for other in items:
		if other != it and other.rect().intersects(r):
			return false
	return true

func _in_zone(tile: Vector2i, item_size: Vector2i) -> bool:
	var r := Rect2i(tile, item_size)
	for z in forbidden:
		if z.intersects(r):
			return true
	return false

func _finish_drag() -> void:
	var it := _drag_item
	if not _in_zone(it.tile, it.size):
		return
	if _drag_rot_delta != 0:
		item_rotated.emit(it, -_drag_rot_delta)
	it.tile = _drag_start_tile
	it.size = _drag_start_size
	_drag_rot_delta = 0
	item_moved.emit(it)
	queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var cell := _mouse_to_tile(event.position)
			var it := _item_at(cell)
			selected = it
			if it != null:
				_drag_item = it
				_grab_offset = cell - it.tile
				_drag_start_tile = it.tile
				_drag_start_size = it.size
				_drag_rot_delta = 0
				_drag_moved = false
		else:
			if _drag_item != null:
				var clicked_item := _drag_item
				var was_click := not _drag_moved
				_finish_drag()
				_drag_item = null
				if was_click:
					item_clicked.emit(clicked_item)
		_update_hover()
	elif event is InputEventMouseMotion:
		if _drag_item != null:
			var new_tile := _mouse_to_tile(event.position) - _grab_offset
			if new_tile != _drag_item.tile and _can_place(_drag_item, new_tile, _drag_item.size):
				_drag_item.tile = new_tile
				_drag_moved = true
				item_moved.emit(_drag_item)
		_update_hover()

# Rotates the dragged item, else the item under the mouse, else the last selected one.
func try_rotate(clockwise: bool) -> bool:
	var mouse_cell := _mouse_to_tile(get_local_mouse_position())
	var it: Item = _drag_item
	if it == null:
		it = _item_at(mouse_cell)
	if it == null:
		it = selected
	if it == null or not it.tag.movable:
		return false

	var w := it.size.x
	var h := it.size.y
	var off: Vector2i
	if it == _drag_item:
		off = _grab_offset
	elif it.rect().has_point(mouse_cell):
		off = mouse_cell - it.tile
	else:
		off = Vector2i(floori(w / 2.0), floori(h / 2.0))

	var new_off: Vector2i
	if clockwise:
		new_off = Vector2i(h - 1 - off.y, off.x)
	else:
		new_off = Vector2i(off.y, w - 1 - off.x)

	var new_size := Vector2i(h, w)
	var new_tile := it.tile + off - new_off
	if not _can_place(it, new_tile, new_size):
		return false
	if it != _drag_item and _in_zone(new_tile, new_size):
		return false

	it.tile = new_tile
	it.size = new_size
	if it == _drag_item:
		_grab_offset = new_off
		_drag_rot_delta += 1 if clockwise else -1
		_drag_moved = true
	selected = it
	item_rotated.emit(it, 1 if clockwise else -1)
	item_moved.emit(it)
	_update_hover()
	queue_redraw()
	return true

func _draw() -> void:
	var cp := _cell_px()
	var o := _origin_px()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.05, 0.07))
	draw_rect(Rect2(o, Vector2(GRID_W, GRID_H) * cp), Color(0.12, 0.12, 0.15))
	for x in GRID_W:
		for y in GRID_H:
			draw_rect(Rect2(o + Vector2(x, y) * cp, Vector2(cp, cp)), Color(0.3, 0.3, 0.35), false, 1.0)
	for z in forbidden:
		draw_rect(Rect2(o + Vector2(z.position) * cp, Vector2(z.size) * cp), Color(0.05, 0.05, 0.07))
	for it in items:
		var r := Rect2(o + Vector2(it.tile) * cp, Vector2(it.size) * cp)
		var c: Color = it.tag.color
		if not it.tag.movable:
			c = c.darkened(0.35)
		if it == _drag_item and _in_zone(it.tile, it.size):
			c = c.lerp(Color(0.9, 0.2, 0.2), 0.6)
		draw_rect(r, c)
	if hovered != null:
		var hr := Rect2(o + Vector2(hovered.tile) * cp, Vector2(hovered.size) * cp)
		var oc := Color(1, 0.9, 0.2) if hovered.tag.movable else Color(0.7, 0.7, 0.7)
		draw_rect(hr, oc, false, 3.0)
		_draw_label(hovered.tag.get_display_name())
