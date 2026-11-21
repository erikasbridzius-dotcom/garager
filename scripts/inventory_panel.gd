class_name InventoryPanel
extends Control

signal all_closed
signal hand_changed(index: int, entry: Dictionary)  # index 0 = left hand, 1 = right hand

const PAD := 14.0
const TITLE_H := 34.0
const HAND_ZONE_H := 90.0

class Win:
	var tag: FurnitureTag
	var pos := Vector2.ZERO
	var cp := 28.0

var windows: Array[Win] = []
var hands: Array[Dictionary] = [{}, {}]

var show_hands := true:
	set(value):
		if value != show_hands:
			show_hands = value
			queue_redraw()

var _drag_win: Win = null
var _drag_off := Vector2.ZERO

var _held: Dictionary = {}
var _held_src: FurnitureTag = null   # the furniture it came from (null if it came from a hand)
var _held_src_hand := -1             # the hand it came from (-1 if it came from furniture)
var _held_src_tile := Vector2i.ZERO
var _held_src_size := Vector2i.ONE
var _held_off := Vector2i.ZERO

# ---------- public API ----------

func has_windows() -> bool:
	return not windows.is_empty()

func take_from_hand(i: int) -> Dictionary:
	var item := hands[i]
	hands[i] = {}
	hand_changed.emit(i, hands[i])
	queue_redraw()
	return item

func give_to_free_hand(entry: Dictionary) -> bool:
	for i in 2:
		if hands[i].is_empty():
			entry["tile"] = Vector2i.ZERO
			hands[i] = entry
			hand_changed.emit(i, entry)
			queue_redraw()
			return true
	return false

func blocks_point(p: Vector2) -> bool:
	if not _held.is_empty() or _drag_win != null or _win_at(p) != null:
		return true
	return show_hands and _hand_at(p) >= 0

# Only claim mouse events over a window or an occupied hand slot, so everything else passes through
func _has_point(point: Vector2) -> bool:
	return blocks_point(point)

func open(t: FurnitureTag) -> void:
	for existing in windows:
		if existing.tag == t:
			_bring_to_front(existing)
			queue_redraw()
			return
	var w := Win.new()
	w.tag = t
	var cells := t.inventory_cells()
	var fit_h := (size.y * 0.8 - PAD * 2.0 - TITLE_H) / cells.y
	var fit_w := (size.x * 0.4 - PAD * 2.0) / cells.x
	w.cp = clampf(floorf(minf(fit_h, fit_w)), 12.0, 36.0)
	var b := _box(w)
	w.pos = (size - b.size) / 2.0 + Vector2(30, 30) * windows.size()
	_clamp_pos(w)
	windows.append(w)
	queue_redraw()

func close_window(w: Win) -> void:
	windows.erase(w)
	if windows.is_empty():
		all_closed.emit()
	queue_redraw()

func close_all() -> void:
	var had := not windows.is_empty()
	if not _held.is_empty():
		_return_held()
		_held = {}
	windows.clear()
	if had:
		all_closed.emit()
	queue_redraw()

# ---------- geometry ----------

func _box(w: Win) -> Rect2:
	var c := w.tag.inventory_cells()
	return Rect2(w.pos, Vector2(c.x * w.cp + PAD * 2.0, c.y * w.cp + PAD * 2.0 + TITLE_H))

func _grid_origin(w: Win) -> Vector2:
	return w.pos + Vector2(PAD, PAD + TITLE_H)

func _close_rect(w: Win) -> Rect2:
	var b := _box(w)
	return Rect2(b.end.x - 28.0, b.position.y + 6.0, 22.0, 22.0)

func _title_rect(w: Win) -> Rect2:
	var b := _box(w)
	return Rect2(b.position, Vector2(b.size.x, PAD + TITLE_H))

func _hand_slot_rect(i: int) -> Rect2:
	var x := 30.0 if i == 0 else size.x - 30.0 - 90.0
	return Rect2(x, size.y - 100.0, 90.0, 90.0)

func _hand_at(p: Vector2) -> int:
	for i in 2:
		if not hands[i].is_empty() and _hand_slot_rect(i).has_point(p):
			return i
	return -1

func _in_hand_zone(p: Vector2) -> bool:
	return p.y >= size.y - HAND_ZONE_H

# Which hand receives an item dropped at p: the side you drop on, else the free one
func _target_hand(p: Vector2) -> int:
	var pref := 0 if p.x < size.x / 2.0 else 1
	if hands[pref].is_empty():
		return pref
	var other := 1 - pref
	if hands[other].is_empty():
		return other
	return -1

func _clamp_pos(w: Win) -> void:
	var b := _box(w)
	w.pos.x = clampf(w.pos.x, 0.0, maxf(0.0, size.x - b.size.x))
	w.pos.y = clampf(w.pos.y, 0.0, maxf(0.0, size.y - b.size.y))

func _win_at(p: Vector2) -> Win:
	for i in range(windows.size() - 1, -1, -1):
		if _box(windows[i]).has_point(p):
			return windows[i]
	return null

func _bring_to_front(w: Win) -> void:
	windows.erase(w)
	windows.append(w)

func _cell_in(w: Win, p: Vector2) -> Vector2i:
	var q := (p - _grid_origin(w)) / w.cp
	return Vector2i(floori(q.x), floori(q.y))

func _in_grid(w: Win, cell: Vector2i) -> bool:
	var c := w.tag.inventory_cells()
	return cell.x >= 0 and cell.y >= 0 and cell.x < c.x and cell.y < c.y

func _entry_at(tag: FurnitureTag, cell: Vector2i) -> int:
	for i in range(tag.stored.size() - 1, -1, -1):
		var e: Dictionary = tag.stored[i]
		var t: Vector2i = e["tile"]
		var s: Vector2i = e["size"]
		if Rect2i(t, s).has_point(cell):
			return i
	return -1

func _fits(tag: FurnitureTag, tile: Vector2i, isize: Vector2i) -> bool:
	var c := tag.inventory_cells()
	if tile.x < 0 or tile.y < 0 or tile.x + isize.x > c.x or tile.y + isize.y > c.y:
		return false
	var r := Rect2i(tile, isize)
	for e in tag.stored:
		var t: Vector2i = e["tile"]
		var s: Vector2i = e["size"]
		if Rect2i(t, s).intersects(r):
			return false
	return true

# ---------- input ----------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				_on_release(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and not _held.is_empty():
			_return_held()
			_held = {}
			queue_redraw()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag_win != null:
			_drag_win.pos = mm.position - _drag_off
			_clamp_pos(_drag_win)
		if _drag_win != null or not _held.is_empty():
			queue_redraw()

func _on_press(p: Vector2) -> void:
	var w := _win_at(p)
	if w == null:
		# No window here: maybe the player is taking an item out of a hand
		var hi := _hand_at(p) if show_hands else -1
		if hi >= 0:
			_held = hands[hi]
			hands[hi] = {}
			var hs: Vector2i = _held["size"]
			_held_src = null
			_held_src_hand = hi
			_held_src_tile = Vector2i.ZERO
			_held_src_size = hs
			_held_off = Vector2i(floori(hs.x / 2.0), floori(hs.y / 2.0))
			hand_changed.emit(hi, hands[hi])
			queue_redraw()
		return
	_bring_to_front(w)
	if _close_rect(w).has_point(p):
		close_window(w)
		return
	if _title_rect(w).has_point(p):
		_drag_win = w
		_drag_off = p - w.pos
		queue_redraw()
		return
	var cell := _cell_in(w, p)
	if _in_grid(w, cell):
		var idx := _entry_at(w.tag, cell)
		if idx >= 0:
			var e: Dictionary = w.tag.stored[idx]
			w.tag.stored.remove_at(idx)
			_held = e
			_held_src = w.tag
			_held_src_hand = -1
			_held_src_tile = e["tile"]
			_held_src_size = e["size"]
			_held_off = cell - _held_src_tile
	queue_redraw()

func _on_release(p: Vector2) -> void:
	_drag_win = null
	if _held.is_empty():
		return
	var placed := false
	var w := _win_at(p)
	if w != null:
		var cell := _cell_in(w, p)
		var tile := cell - _held_off
		var hsize: Vector2i = _held["size"]
		if _in_grid(w, cell) and _fits(w.tag, tile, hsize):
			_held["tile"] = tile
			w.tag.stored.append(_held)
			placed = true
	elif show_hands and _in_hand_zone(p):
		var th := _target_hand(p)
		if th >= 0:
			_held["tile"] = Vector2i.ZERO
			hands[th] = _held
			hand_changed.emit(th, hands[th])
			placed = true
	if not placed:
		_return_held()
	_held = {}
	queue_redraw()

func _return_held() -> void:
	_held["tile"] = _held_src_tile
	_held["size"] = _held_src_size
	if _held_src_hand >= 0:
		hands[_held_src_hand] = _held
		hand_changed.emit(_held_src_hand, hands[_held_src_hand])
	else:
		_held_src.stored.append(_held)

func _rotate_held(clockwise: bool) -> void:
	var s: Vector2i = _held["size"]
	var off := _held_off
	var new_off: Vector2i
	if clockwise:
		new_off = Vector2i(s.y - 1 - off.y, off.x)
	else:
		new_off = Vector2i(off.y, s.x - 1 - off.x)
	_held["size"] = Vector2i(s.y, s.x)
	_held_off = new_off
	queue_redraw()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_ESCAPE:
		if not _held.is_empty():
			_return_held()
			_held = {}
			queue_redraw()
		elif not windows.is_empty():
			close_window(windows[windows.size() - 1])
		else:
			return
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_R and not _held.is_empty():
		_rotate_held(not event.shift_pressed)
		get_viewport().set_input_as_handled()

# ---------- drawing ----------

func _draw() -> void:
	var font := ThemeDB.fallback_font
	if show_hands:
		_draw_hands(font)
	for w in windows:
		_draw_window(w, font)
	if not _held.is_empty():
		_draw_held(font)

func _draw_hands(font: Font) -> void:
	var holding := not _held.is_empty()
	if not holding and hands[0].is_empty() and hands[1].is_empty():
		return
	var mp := get_local_mouse_position()
	var target := -1
	if holding:
		var any_free := hands[0].is_empty() or hands[1].is_empty()
		var band := Color(0.2, 0.7, 0.4, 0.28) if any_free else Color(0.8, 0.25, 0.25, 0.28)
		if _in_hand_zone(mp) and _win_at(mp) == null:
			band.a = 0.5
			target = _target_hand(mp)
		draw_rect(Rect2(0, size.y - HAND_ZONE_H, size.x, HAND_ZONE_H), band)
		var label := "Drop to hold" if any_free else "Hands full"
		draw_string(font, Vector2(0, size.y - HAND_ZONE_H + 18.0), label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, 14, Color(1, 1, 1, 0.85))
	for i in 2:
		var item: Dictionary = hands[i]
		if item.is_empty() and not holding:
			continue
		var slot := _hand_slot_rect(i)
		draw_rect(slot, Color(0.1, 0.1, 0.13, 0.9))
		var edge := Color(1, 0.9, 0.2) if i == target else Color(0.5, 0.5, 0.6)
		draw_rect(slot, edge, false, 3.0 if i == target else 2.0)
		if item.is_empty():
			var side := "Left hand" if i == 0 else "Right hand"
			draw_string(font, slot.position + Vector2(0, 50), side,
				HORIZONTAL_ALIGNMENT_CENTER, slot.size.x, 14, Color(1, 1, 1, 0.5))
			continue
		var s: Vector2i = item["size"]
		var col: Color = item["color"]
		var nm: String = item["name"]
		var cp := minf(minf((slot.size.x - 12.0) / s.x, (slot.size.y - 12.0) / s.y), 28.0)
		_draw_item(font, slot.get_center() - Vector2(s) * cp / 2.0, cp, s, col, nm, 1.0)

func _draw_window(w: Win, font: Font) -> void:
	var box := _box(w)
	var gp := _grid_origin(w)
	var cells := w.tag.inventory_cells()
	var big := w.tag.inventory_big_cells
	var sub := float(w.tag.inventory_sub)

	draw_rect(box.grow(3.0), Color(0, 0, 0, 0.35))
	draw_rect(box, Color(0.1, 0.1, 0.13))
	draw_rect(Rect2(box.position, Vector2(box.size.x, PAD * 0.5 + TITLE_H)), Color(0.17, 0.17, 0.22))
	draw_rect(box, Color(0.4, 0.4, 0.5), false, 2.0)
	draw_string(font, box.position + Vector2(PAD, PAD + 14.0), w.tag.get_display_name(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	var cr := _close_rect(w)
	draw_rect(cr, Color(0.35, 0.15, 0.15))
	draw_string(font, cr.position + Vector2(6, 17), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

	for bx in big.x:
		for by in big.y:
			var shade := Color(0.15, 0.15, 0.19) if (bx + by) % 2 == 0 else Color(0.18, 0.18, 0.23)
			draw_rect(Rect2(gp + Vector2(bx, by) * w.cp * sub, Vector2(w.cp, w.cp) * sub), shade)
	for x in cells.x:
		for y in cells.y:
			draw_rect(Rect2(gp + Vector2(x, y) * w.cp, Vector2(w.cp, w.cp)), Color(0.28, 0.28, 0.34), false, 1.0)
	for bx in big.x:
		for by in big.y:
			draw_rect(Rect2(gp + Vector2(bx, by) * w.cp * sub, Vector2(w.cp, w.cp) * sub), Color(0.6, 0.6, 0.7), false, 2.0)

	for e in w.tag.stored:
		var t: Vector2i = e.get("tile", Vector2i.ZERO)
		var s: Vector2i = e.get("size", Vector2i.ONE)
		var col: Color = e.get("color", Color.WHITE)
		var nm: String = e.get("name", "?")
		_draw_item(font, gp + Vector2(t) * w.cp, w.cp, s, col, nm, 1.0)

func _draw_held(font: Font) -> void:
	var p := get_local_mouse_position()
	var hsize: Vector2i = _held["size"]
	var col: Color = _held["color"]
	var nm: String = _held["name"]
	var w := _win_at(p)
	if w != null:
		var cell := _cell_in(w, p)
		if _in_grid(w, cell):
			var tile := cell - _held_off
			var tint: Color = col if _fits(w.tag, tile, hsize) else Color(0.9, 0.2, 0.2)
			_draw_item(font, _grid_origin(w) + Vector2(tile) * w.cp, w.cp, hsize, tint, nm, 0.8)
			return
	var cp := 28.0
	if not windows.is_empty():
		cp = windows[windows.size() - 1].cp
	var pos := p - (Vector2(_held_off) + Vector2(0.5, 0.5)) * cp
	_draw_item(font, pos, cp, hsize, col, nm, 0.8)

func _draw_item(font: Font, pos: Vector2, cp: float, isize: Vector2i, col: Color, nm: String, alpha: float) -> void:
	var r := Rect2(pos, Vector2(isize) * cp).grow(-2.0)
	draw_rect(r, Color(col.r, col.g, col.b, alpha))
	draw_string(font, r.position + Vector2(4, 14), nm, HORIZONTAL_ALIGNMENT_LEFT,
		maxf(r.size.x - 6.0, 1.0), 12, Color(1, 1, 1, alpha))
